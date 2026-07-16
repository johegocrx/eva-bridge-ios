//
//  VoiceService.swift
//  Eva Copilot
//
//  Servicio de escucha continua (foreground). Sin wake word en español.
//  Flujo:
//    1. App se abre → permisos → empieza a escuchar en silencio
//    2. Usuario dice algo en español → recognizer transcribe
//    3. Cuando termina la utterance (silencio) → busca match en catálogo
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

    private let speech: SpeechManager
    private let tts: TTSManager
    private let matcher: CatalogMatcher

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
            // Solo auto-reiniciar si estamos en modo listening
            if self.state == .listening {
                self.beginListeningCycle()
            }
        }
    }

    func start() async {
        let granted = await speech.requestPermissions()
        self.permissionGranted = granted
        if granted {
            // NO hablar al abrir: entrar directo en modo escucha silenciosa
            beginListeningCycle()
        }
    }

    func stop() {
        speech.stopListening()
        tts.stop()
        state = .stopped
        infoMessage = "Detenido. Toca el micrófono para reiniciar."
    }

    private func beginListeningCycle() {
        state = .listening
        infoMessage = "Decí tu comando en español"
        lastTranscript = ""
        speech.startListening()
    }

    private func handlePartial(_ text: String) {
        // Solo mostrar el transcript parcial. NO procesar todavía.
        lastTranscript = text
    }

    private func handleFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = trimmed
        guard !trimmed.isEmpty else {
            // Recognizer terminó con texto vacío (ej. solo ruido/silencio)
            // Reiniciar ciclo
            beginListeningCycle()
            return
        }
        processCommand(trimmed)
    }

    private func processCommand(_ text: String) {
        state = .translating
        speech.stopListening()

        // Comandos de stop
        if WakeWordDetector.isStopCommand(text) {
            tts.speak("好的")
            state = .stopped
            infoMessage = "Decí \"adiós\" o tocá el micrófono para reiniciar."
            return
        }

        // Buscar en catálogo
        let results = matcher.search(text)
        if let best = results.first {
            lastMatch = best.command
            infoMessage = "→ \(best.command.zh)"
            state = .speaking
            // Decir "嗨伊娃" + comando en chino
            tts.speak("嗨伊娃", completion: { [weak self] in
                guard let self = self else { return }
                self.tts.speakCommand(best.command, completion: { [weak self] in
                    // Después de hablar, volver a escuchar
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self?.beginListeningCycle()
                    }
                })
            })
        } else {
            infoMessage = "Sin coincidencia. Probá de nuevo."
            tts.speak("抱歉，我没听清", completion: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self?.beginListeningCycle()
                }
            })
        }
    }
}
