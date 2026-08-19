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

    private var recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// true = el user detuvo manualmente (o estamos en .stopped).
    /// El audio engine sigue activo (si está corriendo) pero el caller es
    /// responsable de descartar los resultados.
    private var manuallyStopped: Bool = true
    /// Locale actual del recognizer (es-MX, en-US, ru-RU). Se puede cambiar
    /// en runtime con `setLocale()`.
    private var currentLocale: String = "es-MX"

    override init() {
        // Cargar locale persistido
        let saved = UserDefaults.standard.string(forKey: "speechLocale") ?? "es-MX"
        self.currentLocale = saved
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: saved))
        super.init()
        self.recognizer?.delegate = self
        self.onDeviceSupported = self.recognizer?.supportsOnDeviceRecognition ?? false
        if !self.onDeviceSupported {
            self.status = "On-device no soportado. Se usará servidor."
        }
    }

    /// Cambia el locale del recognizer. Si está activo, lo reinicia.
    func setLocale(_ locale: String) {
        guard ["es-MX", "en-US", "ru-RU"].contains(locale) else { return }
        guard locale != currentLocale else { return }
        currentLocale = locale
        UserDefaults.standard.set(locale, forKey: "speechLocale")

        let wasActive = isListening
        if wasActive {
            stopListening()
        }

        recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        recognizer?.delegate = self
        onDeviceSupported = recognizer?.supportsOnDeviceRecognition ?? false
        status = "Idioma cambiado a \(displayName(locale))"

        if wasActive {
            // El caller (VoiceService) puede llamar a startListening() de nuevo
        }
    }

    /// Nombre display del locale actual
    var currentLocaleDisplay: String { displayName(currentLocale) }

    private func displayName(_ locale: String) -> String {
        switch locale {
        case "es-MX": return "Español"
        case "en-US": return "English"
        case "ru-RU": return "Русский"
        default: return locale
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
            // .voiceChat permite grabar Y reproducir, evitando que el TTS
            // quede silenciado cuando el recognizer está activo.
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
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

    /// Pausa el listener sin matar el audio engine. Los callbacks de
    /// partial/final siguen llamándose pero el caller es responsable de
    /// decidir qué hacer (típicamente descartar).
    ///
    /// Usado por la mejora #6: cuando VoiceService está en .stopped, el
    /// recognizer sigue activo para detectar "oye yoe" y reanudar.
    func pauseListening() {
        manuallyStopped = true
    }

    /// Resume el listener (lo despausa). El audio engine debe seguir
    /// corriendo. Usado por la mejora #6 cuando el user dice "oye yoe"
    /// en estado .stopped.
    func resumeListening() {
        manuallyStopped = false
    }

    /// Indica si el listener está pausado (manualmente).
    var isPaused: Bool { manuallyStopped }

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
