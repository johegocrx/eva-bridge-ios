//
//  TTSManager.swift
//  Eva Copilot
//
//  Text-to-Speech en chino mandarín para comunicarse con EVA.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published var isSpeaking: Bool = false
    @Published var status: String = ""
    @Published var lastError: String?
    @Published var voiceName: String = "—"
    /// True si hay una voz china instalada
    @Published var hasChineseVoice: Bool = false

    private let synthesizer = AVSpeechSynthesizer()
    private var zhVoice: AVSpeechSynthesisVoice?
    private var esVoice: AVSpeechSynthesisVoice?
    private var enVoice: AVSpeechSynthesisVoice?
    private var ruVoice: AVSpeechSynthesisVoice?
    private var pendingCallback: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        self.zhVoice = pickBestChineseVoice()
        self.esVoice = pickBestSpanishVoice()
        self.enVoice = pickBestEnglishVoice()
        self.ruVoice = pickBestRussianVoice()
        self.voiceName = self.zhVoice?.name ?? "No instalada"
        self.hasChineseVoice = (self.zhVoice != nil)
        if self.zhVoice == nil {
            self.lastError = "Voz china no instalada. Ajustes → Accesibilidad → Contenido hablado → Voces → Chino (mandarín)."
        }
        // Configurar sesión de audio para reproducción (TTS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt,
                                    options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // No crítico; TTS puede funcionar sin configurar sesión
        }
    }

    private func pickBestChineseVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let v = voices.first(where: { $0.quality == .premium && $0.language == "zh-CN" }) { return v }
        if let v = voices.first(where: { $0.quality == .enhanced && $0.language == "zh-CN" }) { return v }
        if let v = voices.first(where: { $0.language == "zh-CN" }) { return v }
        if let v = voices.first(where: { $0.language.hasPrefix("zh") }) { return v }
        return nil
    }

    private func pickBestSpanishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let v = voices.first(where: { $0.quality == .premium && $0.language == "es-MX" }) { return v }
        if let v = voices.first(where: { $0.quality == .enhanced && $0.language == "es-MX" }) { return v }
        if let v = voices.first(where: { $0.language == "es-MX" }) { return v }
        if let v = voices.first(where: { $0.quality == .premium && $0.language == "es-ES" }) { return v }
        if let v = voices.first(where: { $0.quality == .enhanced && $0.language == "es-ES" }) { return v }
        if let v = voices.first(where: { $0.language == "es-ES" }) { return v }
        if let v = voices.first(where: { $0.language.hasPrefix("es") }) { return v }
        return nil
    }

    private func pickBestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let v = voices.first(where: { $0.quality == .premium && $0.language == "en-US" }) { return v }
        if let v = voices.first(where: { $0.quality == .enhanced && $0.language == "en-US" }) { return v }
        if let v = voices.first(where: { $0.language == "en-US" }) { return v }
        if let v = voices.first(where: { $0.quality == .premium && $0.language.hasPrefix("en") }) { return v }
        if let v = voices.first(where: { $0.language.hasPrefix("en") }) { return v }
        return nil
    }

    private func pickBestRussianVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let v = voices.first(where: { $0.quality == .premium && $0.language == "ru-RU" }) { return v }
        if let v = voices.first(where: { $0.quality == .enhanced && $0.language == "ru-RU" }) { return v }
        if let v = voices.first(where: { $0.language == "ru-RU" }) { return v }
        if let v = voices.first(where: { $0.language.hasPrefix("ru") }) { return v }
        return nil
    }

    /// Nombres display para debug/UI
    var spanishVoiceName: String { esVoice?.name ?? "—" }
    var englishVoiceName: String { enVoice?.name ?? "—" }
    var russianVoiceName: String { ruVoice?.name ?? "—" }

    /// Dice un texto (uso general). Opcional: completion al terminar.
    /// Por defecto usa la voz china (para los comandos que van a EVA).
    /// Usar `speakInLocale()` para prompts en el idioma del user.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        speak(text, voice: zhVoice, completion: completion)
    }

    /// Dice un texto en español (para los prompts y feedback al user).
    /// Si no hay voz española instalada, hace fallback a la voz china.
    func speakInSpanish(_ text: String, completion: (() -> Void)? = nil) {
        speak(text, voice: esVoice ?? zhVoice, completion: completion)
    }

    /// Dice un texto en inglés.
    /// Si no hay voz inglesa instalada, hace fallback a español o chino.
    func speakInEnglish(_ text: String, completion: (() -> Void)? = nil) {
        speak(text, voice: enVoice ?? esVoice ?? zhVoice, completion: completion)
    }

    /// Dice un texto en ruso.
    /// Si no hay voz rusa instalada, hace fallback a español o chino.
    func speakInRussian(_ text: String, completion: (() -> Void)? = nil) {
        speak(text, voice: ruVoice ?? esVoice ?? zhVoice, completion: completion)
    }

    /// Dice un texto usando la voz del locale del ASR (es/en/ru).
    /// Fallback chain: locale → es → zh.
    func speakInLocale(_ text: String, locale: String, completion: (() -> Void)? = nil) {
        let voice: AVSpeechSynthesisVoice?
        switch locale {
        case "en-US":
            voice = enVoice ?? esVoice ?? zhVoice
        case "ru-RU":
            voice = ruVoice ?? esVoice ?? zhVoice
        case "es-MX":
            voice = esVoice ?? zhVoice
        default:
            voice = zhVoice
        }
        speak(text, voice: voice, completion: completion)
    }

    private func speak(_ text: String, voice: AVSpeechSynthesisVoice?, completion: (() -> Void)?) {
        guard let v = voice, !text.isEmpty else {
            completion?()
            return
        }
        // Si está hablando algo, lo cancelamos
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        // Asegurar que la sesión de audio permite reproducción
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt,
                                    options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Continuar de todas formas
        }
        isSpeaking = true
        let utter = AVSpeechUtterance(string: text)
        utter.voice = v
        utter.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utter.pitchMultiplier = 1.0
        utter.volume = 1.0
        utter.preUtteranceDelay = 0.05
        pendingCallback = completion
        synthesizer.speak(utter)
    }

    /// Dice el comando en chino. Opcional: completion al terminar.
    func speakCommand(_ cmd: EvaCommand, completion: (() -> Void)? = nil) {
        speak(cmd.zh, completion: completion)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        pendingCallback = nil
    }

    func shutdown() {
        stop()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let cb = self.pendingCallback
            self.pendingCallback = nil
            self.isSpeaking = false
            cb?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.pendingCallback = nil
        }
    }
}
