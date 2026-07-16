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

    private let synthesizer = AVSpeechSynthesizer()
    private var zhVoice: AVSpeechSynthesisVoice?
    private var pendingCallback: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        self.zhVoice = pickBestChineseVoice()
        self.voiceName = self.zhVoice?.name ?? "No disponible"
        if self.zhVoice == nil {
            self.lastError = "No hay voz china instalada. Ajustes → Accesibilidad → Voz en voz alta → Chino."
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

    /// Dice un texto (uso general). Opcional: completion al terminar.
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        guard let zh = zhVoice, !text.isEmpty else {
            completion?()
            return
        }
        // Si está hablando algo, lo cancelamos
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = true
        let utter = AVSpeechUtterance(string: text)
        utter.voice = zh
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
