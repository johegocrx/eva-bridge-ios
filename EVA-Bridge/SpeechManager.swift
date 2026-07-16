//
//  SpeechManager.swift
//  Eva Copilot
//
//  Speech recognition on-device en español, con auto-restart continuo.
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {

    @Published var isListening: Bool = false
    @Published var transcript: String = ""
    @Published var status: String = "Listo para escuchar"
    @Published var error: String?
    @Published var onDeviceSupported: Bool = false

    // Callbacks para integración con VoiceService
    var onFinalResult: ((String) -> Void)?
    var onPartialResult: ((String) -> Void)?
    /// Se llama cuando el listener termina por su cuenta (timeout, error)
    /// y debería ser reiniciado. NO se llama cuando se detiene manualmente.
    var onAutoRestartNeeded: (() -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var manuallyStopped: Bool = true

    override init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
        super.init()
        self.recognizer?.delegate = self
        self.onDeviceSupported = self.recognizer?.supportsOnDeviceRecognition ?? false
        if !self.onDeviceSupported {
            self.status = "On-device no soportado. Se usará servidor."
        }
    }

    func requestPermissions() async -> Bool {
        let speechOK: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK: Bool = await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        if !speechOK { self.error = "Permiso de reconocimiento de voz denegado" }
        if !micOK { self.error = "Permiso de micrófono denegado" }
        return speechOK && micOK
    }

    func hasPermission() -> Bool {
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func startListening() {
        guard !isListening else { return }
        if !hasPermission() {
            self.error = "Sin permiso de micrófono"
            return
        }
        manuallyStopped = false

        task?.cancel()
        task = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: [])
        } catch {
            self.error = "Error audio session: \(error.localizedDescription)"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if self.onDeviceSupported {
            req.requiresOnDeviceRecognition = true
        }
        self.request = req

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "Error iniciando audio: \(error.localizedDescription)"
            return
        }

        isListening = true
        transcript = ""
        status = "🎙️ Escuchando..."
        error = nil

        self.task = self.recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    if result.isFinal {
                        // El recognizer dio un resultado final. NO cerramos
                        // el listener: dejamos que siga escuchando la
                        // siguiente utterance.
                        self.onFinalResult?(text)
                    } else {
                        self.onPartialResult?(text)
                    }
                }
                if let error = error as NSError? {
                    let msg = error.localizedDescription
                    // 203 = No speech detected, 1110 = timeout. Son normales.
                    // El recognizer terminó por sí solo.
                    let isBenign = error.code == 203
                        || error.code == 1110
                        || msg.lowercased().contains("canceled")
                    self.cleanupAudioEngine()
                    if isBenign {
                        // Reanudar escucha automáticamente
                        if !self.manuallyStopped {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                                guard let self = self, !self.manuallyStopped else { return }
                                self.onAutoRestartNeeded?()
                            }
                        }
                    } else {
                        self.error = msg
                        self.status = "Error: \(msg)"
                    }
                }
            }
        }
    }

    func stopListening() {
        manuallyStopped = true
        cleanupAudioEngine()
    }

    private func cleanupAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
    }

    func shutdown() {
        stopListening()
    }
}
