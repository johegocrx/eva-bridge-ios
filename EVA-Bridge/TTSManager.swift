//
//  TTSManager.swift
//  Eva Copilot
//
//  Text-to-Speech en chino mandarín para comunicarse con EVA.
//  Voice: prefers zh-CN premium quality.
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
            self.lastError = "No hay voz china instalada. Ajustes → Teclado → Chino simplificado."
        }
    }

    private func pickBestChineseVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        // 1) Premium zh-CN
        if let v = voices.first(where: { $0.quality == .premium && $0.language == "zh-CN" }) { return v }
        // 2) Enhanced zh-CN
        if let v = voices.first(where: { $0.quality == .enhanced && $0.language == "zh-CN" }) { return v }
        // 3) Cualquier zh-CN
        if let v = voices.first(where: { $0.language == "zh-CN" }) { return v }
        // 4) Cualquier zh
        if let v = voices.first(where: { $0.language.hasPrefix("zh") }) { return v }
        return nil
    }

    /// Dice un texto (uso general).
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        guard let zh = zhVoice, !text.isEmpty else { completion?(); return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = true
        let utter = AVSpeechUtterance(string: text)
        utter.voice = zh
        utter.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utter.pitchMultiplier = 1.0
        utter.volume = 1.0
        utter.preUtteranceDelay = 0.05
        if completion != nil {
            pendingCallback = completion
        } else {
            pendingCallback = nil
        }
        synthesizer.speak(utter)
    }

    /// Habla la wake word china "嗨伊娃" (despierta a EVA).
    /// Luego, si hay un callback, lo ejecuta (para el comando).
    func speakWakeWord(completion: (() -> Void)? = nil) {
        speak("嗨伊娃", completion: completion)
    }

    /// Dice el comando en chino.
    func speakCommand(_ cmd: EvaCommand) {
        speak(cmd.zh)
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
            if let cb = self.pendingCallback {
                self.pendingCallback = nil
                cb()
            } else {
                self.isSpeaking = false
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.pendingCallback = nil
        }
    }
}