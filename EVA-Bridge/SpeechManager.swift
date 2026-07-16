//
//  SpeechManager.swift
//  Eva Copilot
//
//  Speech recognition con on-device, español. Diseñado para escucha cíclica
//  (wake word detection).
//

import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {

    @Published var isListening: Bool = false
    @Published var transcript: String = ""
    @Published var status: String = "Toca el micrófono para hablar"
    @Published var error: String?
    @Published var onDeviceSupported: Bool = false

    // Callbacks para integración con VoiceService
    var onFinalResult: ((String) -> Void)?
    var onPartialResult: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    override init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
        super.init()
        self.recognizer?.delegate = self
        self.onDeviceSupported = self.recognizer?.supportsOnDeviceRecognition ?? false
        if !self.onDeviceSupported {
            self.status = "Reconocimiento on-device no soportado. Se usará servidor."
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

        task?.cancel()
        task = nil

        // Configurar AVAudioSession
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
                        self.onFinalResult?(text)
                    } else {
                        self.onPartialResult?(text)
                    }
                }
                if let error = error as NSError? {
                    self.stopListening()
                    let msg = error.localizedDescription
                    if msg.lowercased().contains("canceled") { return }
                    if error.code == 203 { return } // No speech
                    self.error = msg
                    self.status = "Error: \(msg)"
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
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