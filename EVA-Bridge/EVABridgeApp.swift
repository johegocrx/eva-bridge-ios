//
//  EVABridgeApp.swift
//  Eva Copilot
//

import SwiftUI
import AVFoundation

@main
struct EVABridgeApp: App {
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var ttsManager = TTSManager()
    @StateObject private var matcher = CatalogMatcher()
    @StateObject private var voiceService: VoiceService

    init() {
        let speech = SpeechManager()
        let tts = TTSManager()
        let match = CatalogMatcher()
        _speechManager = StateObject(wrappedValue: speech)
        _ttsManager = StateObject(wrappedValue: tts)
        _matcher = StateObject(wrappedValue: match)
        _voiceService = StateObject(wrappedValue: VoiceService(speech: speech, tts: tts, matcher: match))

        // Configurar sesión de audio
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            print("[Eva Copilot] AVAudioSession setup failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechManager)
                .environmentObject(ttsManager)
                .environmentObject(matcher)
                .environmentObject(voiceService)
        }
    }
}