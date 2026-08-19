//
//  VoiceService.swift
//  Eva Copilot
//
//  Servicio de escucha continua (foreground). Sin wake word en español.
//  Flujo:
//    1. App se abre → permisos → empieza a escuchar en silencio
//    2. Usuario dice algo en español → recognizer transcribe (partials)
//    3. Cuando hay 1.5s de silencio (debounce) o llega final result → busca match
//    4. Dice "嗨伊娃" + comando en chino
//    5. Vuelve a escuchar (auto-ciclo)
//
//  iOS puede suspender la app en background. Funciona bien en foreground
//  (ej. el iPhone apoyado en el soporte del auto, app abierta).
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class VoiceService: ObservableObject {

    enum State: String {
        case idle = "Toca el micrófono"
        case listening = "Escuchando..."
        case translating = "Traduciendo..."
        case speaking = "Hablando a EVA"
        case stopped = "Detenido"
        case awaitingConfirmation = "Esperando tu confirmación"
    }

    @Published var state: State = .idle
    @Published var lastTranscript: String = ""
    @Published var lastMatch: EvaCommand?
    @Published var permissionGranted: Bool = false
    @Published var infoMessage: String = ""
    /// Todos los matches del último comando (para mostrar en la lista)
    @Published var lastMatches: [CatalogMatch] = []
    /// El match pendiente de confirmación cuando el modo seguro lo requiere
    @Published var pendingMatch: CatalogMatch?
    /// Cuando es true, se pide confirmación al usuario antes de ejecutar cualquier
    /// match con confidence < 0.7. Persistido en UserDefaults.
    @AppStorage("safeMode") var safeMode: Bool = true
    /// Umbral de confidence (0-1) por encima del cual se ejecuta sin pedir
    /// confirmación, incluso con modo seguro activado. Ajustable por el user.
    @AppStorage("safeModeThreshold") var safeModeThreshold: Double = 0.7

    private let speech: SpeechManager
    private let tts: TTSManager
    private let matcher: CatalogMatcher
    private let history: CommandHistory

    /// El último input transcrito, para guardar en el historial al ejecutar
    private var lastInputForHistory: String = ""

    // Debounce: si el último partial no cambia por este tiempo, procesar
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 1.5
    private var lastPartialText: String = ""
    private var processing: Bool = false

    init(speech: SpeechManager, tts: TTSManager, matcher: CatalogMatcher, history: CommandHistory) {
        self.speech = speech
        self.tts = tts
        self.matcher = matcher
        self.history = history
        // Callbacks del speech manager
        self.speech.onPartialResult = { [weak self] text in
            self?.handlePartial(text)
        }
        self.speech.onFinalResult = { [weak self] text in
            self?.handleFinal(text)
        }
        // Si el recognizer termina solo (timeout / no speech), reiniciar
        self.speech.onAutoRestartNeeded = { [weak self] in
            guard let self = self else { return }
            if self.state == .listening && !self.processing {
                self.beginListeningCycle()
            }
        }
    }

    func start() async {
        let granted = await speech.requestPermissions()
        self.permissionGranted = granted
        if granted {
            beginListeningCycle()
        }
    }

    func stop() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        speech.stopListening()
        tts.stop()
        state = .stopped
        infoMessage = "Detenido. Toca el micrófono para reiniciar."
    }

    /// Botón de pánico: cancela TODO inmediatamente. Más agresivo que stop().
    /// Usado cuando el user quiere un kill switch de emergencia.
    func panic() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        processing = false
        speech.stopListening()
        tts.stop()
        pendingMatch = nil
        lastMatches = []
        lastMatch = nil
        state = .idle
        infoMessage = "🛑 PÁNICO: todo detenido. Toca el micrófono para reiniciar."
    }

    private func beginListeningCycle() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        processing = false
        state = .listening
        infoMessage = "Decí tu comando en español"
        lastTranscript = ""
        lastPartialText = ""
        lastMatch = nil
        // lastMatches se mantiene para que el usuario vea el último resultado
        speech.startListening()
    }

    private func handlePartial(_ text: String) {
        guard state == .listening, !processing else { return }
        lastTranscript = text
        lastPartialText = text
        lastInputForHistory = text  // para el historial

        // Reiniciar timer de debounce. Cuando el usuario deje de hablar
        // (1.5s sin cambios), procesamos el último texto.
        debounceTimer?.invalidate()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.state == .listening, !self.processing else { return }
                    let t = self.lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        self.processCommand(t)
                    }
                }
            }
        }
    }

    private func handleFinal(_ text: String) {
        // El recognizer dio un final result. Procesar inmediatamente.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = trimmed
        lastInputForHistory = trimmed
        debounceTimer?.invalidate()
        debounceTimer = nil
        guard !trimmed.isEmpty else {
            if !processing && state == .listening {
                beginListeningCycle()
            }
            return
        }
        if !processing {
            processCommand(trimmed)
        }
    }

    private func processCommand(_ text: String) {
        guard !processing else { return }
        processing = true
        debounceTimer?.invalidate()
        debounceTimer = nil
        state = .translating
        speech.stopListening()

        // Comandos de stop
        if WakeWordDetector.isStopCommand(text) {
            tts.speak("好的")
            state = .stopped
            infoMessage = "Decí \"adiós\" o tocá el micrófono para reiniciar."
            lastMatches = []
            pendingMatch = nil
            processing = false
            return
        }

        // Cancelar una confirmación pendiente si el user dice "cancelar", "no", "nada"
        if state == .awaitingConfirmation && WakeWordDetector.isCancelCommand(text) {
            cancelConfirmation()
            return
        }

        // Buscar en catálogo
        let results = matcher.search(text)
        if results.isEmpty {
            handleNoMatch(text: text)
            return
        }

        let best = results.first!

        // MODO SEGURO: si está activado y la confidence del mejor match es baja,
        // NO ejecutar. En su lugar, mostrar candidatos y pedir confirmación.
        if safeMode && best.confidence < safeModeThreshold {
            pendingMatch = best
            lastMatches = Array(results.prefix(5))
            state = .awaitingConfirmation
            infoMessage = "¿Quisiste decir: \"\(best.command.es)\"? Tocá la opción correcta o decí \"cancelar\"."
            speakConfirmationPrompt(options: Array(results.prefix(3)))
            return
        }

        // Confidence alta o modo seguro desactivado → ejecutar
        executeMatch(best, allResults: results)
    }

    /// Ejecuta un match confirmado. Habla el wake word + el comando a EVA y
    /// vuelve a escuchar.
    private func executeMatch(_ match: CatalogMatch, allResults: [CatalogMatch]? = nil) {
        lastMatch = match.command
        if let all = allResults {
            lastMatches = Array(all.prefix(5))
        }
        pendingMatch = nil
        state = .speaking
        infoMessage = "→ \(match.command.zh)"

        // Guardar en historial
        let wasConfirmed = (allResults != nil)  // vino de un confirmMatch()
        let inputSnapshot = lastInputForHistory
        let conf = match.confidence
        history.add(
            inputEs: inputSnapshot,
            command: match.command,
            confidence: conf,
            wasConfirmed: wasConfirmed
        )

        let cmdToRun = match.command
        tts.speak("嗨伊娃", completion: { [weak self] in
            guard let self = self else { return }
            self.tts.speakCommand(cmdToRun, completion: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.beginListeningCycle()
                }
            })
        })
    }

    /// El usuario tocó un candidato en la lista de confirmación. Ejecuta ese
    /// match (no necesariamente el best original).
    func confirmMatch(_ match: CatalogMatch) {
        guard state == .awaitingConfirmation else { return }
        processing = true  // evita que el ciclo de escucha dispare otro processCommand
        executeMatch(match, allResults: lastMatches)
    }

    /// Cancela la confirmación pendiente. Sirve tanto para un toque en la UI
    /// como para el comando de voz "cancelar".
    func cancelConfirmation() {
        pendingMatch = nil
        lastMatches = []
        state = .listening
        infoMessage = "Cancelado. Decí tu comando en español."
        tts.speak("好的", completion: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.beginListeningCycle()
            }
        })
    }

    /// Maneja el caso de no match. Por ahora: pide que reintente.
    /// (La mejora #2 va a ampliar esto para sugerir alternativas por categoría.)
    private func handleNoMatch(text: String) {
        // Intentar encontrar alternativas por categoría antes de rendirse.
        let alternatives = matcher.searchByCategory(text)
        if !alternatives.isEmpty {
            // Mostrar las alternativas como matches (sin confidence, score=0, maxScore=0 → conf=0)
            let altMatches = alternatives.enumerated().map { idx, cmd in
                CatalogMatch(command: cmd, score: 1, maxScore: 10)
            }
            lastMatches = altMatches
            infoMessage = "No encontré ese comando exacto. ¿Quisiste alguna de estas opciones de '\(firstToken(text))'?"
            // Decimos el primer comando como sugerencia
            if let first = alternatives.first {
                tts.speak("¿Quisiste: \(first.es)?", completion: { [weak self] in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.beginListeningCycle()
                    }
                })
            } else {
                beginListeningCycle()
            }
        } else {
            infoMessage = "No te entendí. Probá con otras palabras o tocá el micrófono para reintentar."
            lastMatches = []
            pendingMatch = nil
            tts.speak("抱歉，我没听清", completion: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.beginListeningCycle()
                }
            })
        }
    }

    /// Helper: devuelve la primera palabra significativa del texto.
    private func firstToken(_ text: String) -> String {
        let parts = text.split(separator: " ").map(String.init)
        return parts.first(where: { $0.count > 2 }) ?? text
    }

    /// Pregunta en español si el usuario quiso decir alguno de los candidatos.
    /// (Reproduce en español usando la voz china porque no hay otra voz TTS
    /// configurada; el chino sigue siendo entendible por hispanohablantes.)
    private func speakConfirmationPrompt(options: [CatalogMatch]) {
        guard let first = options.first else { return }
        // Decimos solo la primera opción. El usuario puede tocar otras en la UI
        // o volver a hablar.
        tts.speak("¿Quisiste decir: \(first.command.es)?", completion: nil)
    }
}
