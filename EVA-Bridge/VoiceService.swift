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
    }

    @Published var state: State = .idle
    @Published var lastTranscript: String = ""
    @Published var lastMatch: EvaCommand?
    @Published var permissionGranted: Bool = false
    @Published var infoMessage: String = ""
    /// Todos los matches del último comando (para mostrar en la lista)
    @Published var lastMatches: [CatalogMatch] = []

    private let speech: SpeechManager
    private let tts: TTSManager
    private let matcher: CatalogMatcher

    // Debounce: si el último partial no cambia por este tiempo, procesar
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 1.5
    private var lastPartialText: String = ""
    private var processing: Bool = false

    init(speech: SpeechManager, tts: TTSManager, matcher: CatalogMatcher) {
        self.speech = speech
        self.tts = tts
        self.matcher = matcher
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
            processing = false
            return
        }

        // Buscar en catálogo
        let results = matcher.search(text)
        if let best = results.first {
            lastMatch = best.command
            lastMatches = Array(results.prefix(5))
            infoMessage = "→ \(best.command.zh)"
            state = .speaking
            tts.speak("嗨伊娃", completion: { [weak self] in
                guard let self = self else { return }
                self.tts.speakCommand(best.command, completion: { [weak self] in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.beginListeningCycle()
                    }
                })
            })
        } else {
            infoMessage = "Sin coincidencia. Probá de nuevo."
            lastMatches = []
            tts.speak("抱歉，我没听清", completion: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.beginListeningCycle()
                }
            })
        }
    }
}
