//
//  VoiceService.swift
//  Eva Copilot
//
//  Servicio de escucha continua (foreground) que detecta el wake word "Yoe"
//  y dispara el flujo de comando a EVA.
//
//  Flujo:
//    1. App se abre → servicio arranca
//    2. Cicla: listen 2-3 seg buscando "Yoe" en transcripts
//    3. Si detecta "Yoe" → dice "嗨伊娃" → escucha comando → busca match → dice comando
//    4. Vuelve a ciclar (escuchando "Yoe" de nuevo)
//
//  iOS puede suspender la app en background, pero este servicio
//  funciona mientras la app esté en foreground o el iPhone desbloqueado.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class VoiceService: ObservableObject {

    enum State: String {
        case idle = "Toca el micrófono"
        case listeningWakeWord = "Esperando \"Yoe\""
        case wakeWordDetected = "¡Hola! Decime el comando"
        case listeningCommand = "Escuchando comando"
        case speaking = "Hablando"
        case stopped = "Detenido"
    }

    @Published var state: State = .idle
    @Published var lastTranscript: String = ""
    @Published var lastMatch: EvaCommand?
    @Published var permissionGranted: Bool = false

    private let speech: SpeechManager
    private let tts: TTSManager
    private let matcher: CatalogMatcher
    private var commandResultHandler: ((CatalogMatch) -> Void)?

    init(speech: SpeechManager, tts: TTSManager, matcher: CatalogMatcher) {
        self.speech = speech
        self.tts = tts
        self.matcher = matcher
        // Configurar callbacks del speech manager
        self.speech.onPartialResult = { [weak self] text in
            self?.handlePartial(text)
        }
        self.speech.onFinalResult = { [weak self] text in
            self?.handleFinal(text)
        }
    }

    func start() async {
        let granted = await speech.requestPermissions()
        self.permissionGranted = granted
        if granted {
            tts.speakWakeWord(completion: { [weak self] in
                self?.beginWakeWordCycle()
            })
        }
    }

    func stop() {
        speech.stopListening()
        tts.stop()
        state = .stopped
    }

    private func beginWakeWordCycle() {
        state = .listeningWakeWord
        lastTranscript = ""
        lastMatch = nil
        speech.startListening()
    }

    private func handlePartial(_ text: String) {
        lastTranscript = text
        // Chequear wake word en cada partial result
        if state == .listeningWakeWord && WakeWordDetector.containsWakeWord(text) {
            onWakeWordDetected()
        }
    }

    private func handleFinal(_ text: String) {
        lastTranscript = text
        if state == .listeningWakeWord {
            if WakeWordDetector.containsWakeWord(text) {
                onWakeWordDetected()
            } else {
                // No fue wake word, ciclar
                beginWakeWordCycle()
            }
        } else if state == .listeningCommand {
            onCommandReceived(text)
        }
    }

    private func onWakeWordDetected() {
        speech.stopListening()
        state = .wakeWordDetected
        // Decir la wake word china para despertar a EVA
        tts.speakWakeWord(completion: { [weak self] in
            // Después, escuchar el comando
            self?.beginCommandListening()
        })
    }

    private func beginCommandListening() {
        state = .listeningCommand
        lastTranscript = ""
        speech.startListening()
    }

    private func onCommandReceived(_ text: String) {
        let command = WakeWordDetector.extractCommand(from: text)
        speech.stopListening()

        // Comandos de stop
        if WakeWordDetector.isStopCommand(text) || WakeWordDetector.isStopCommand(command) {
            tts.speak("好的")
            state = .stopped
            return
        }

        // Buscar en catálogo
        let results = matcher.search(command.isEmpty ? text : command)
        if let best = results.first {
            lastMatch = best.command
            tts.speakCommand(best.command)
            commandResultHandler?(best)
        } else {
            // No match
            tts.speak("抱歉，我没听清")
        }
        // Volver a escuchar wake word después de un breve delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.beginWakeWordCycle()
        }
    }
}