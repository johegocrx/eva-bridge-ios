//
//  ContentView.swift
//  Eva Copilot
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var tts: TTSManager
    @EnvironmentObject var matcher: CatalogMatcher
    @EnvironmentObject var voice: VoiceService

    @State private var textInput: String = ""
    @State private var didStart = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            mainContent
        }
        .task {
            // Auto-arrancar el servicio de voz al abrir la app
            if !didStart {
                didStart = true
                await voice.start()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            header
            statusLabel
            voiceIndicator
            inputRow
            resultsList
            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Eva Copilot")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text("Para Zeekr")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(speech.onDeviceSupported ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(speech.onDeviceSupported ? "ON-DEVICE" : "SERVIDOR")
                    .font(.caption2)
                    .foregroundColor(speech.onDeviceSupported ? .green : .orange)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(8)
        }
    }

    private var statusLabel: some View {
        Text(voiceStateText)
            .font(.caption)
            .foregroundColor(voiceStateColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 18)
    }

    private var voiceStateText: String {
        if !voice.permissionGranted {
            return "Concedé permiso de micrófono y voz para empezar"
        }
        if !voice.infoMessage.isEmpty {
            return voice.infoMessage
        }
        switch voice.state {
        case .idle: return "Toca el micrófono para iniciar"
        case .listening: return "🎙️ Escuchando tu comando en español..."
        case .translating: return "🔄 Traduciendo..."
        case .speaking: return "🔊 Hablando a EVA en chino"
        case .stopped: return "⏸️ Detenido"
        }
    }

    private var voiceStateColor: Color {
        switch voice.state {
        case .listening: return .cyan
        case .translating: return .yellow
        case .speaking: return .green
        case .stopped: return .gray
        default: return .gray
        }
    }

    private var voiceIndicator: some View {
        VStack(spacing: 8) {
            Button {
                if voice.state == .stopped || !voice.permissionGranted {
                    Task { await voice.start() }
                } else {
                    voice.stop()
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(stateGradient)
                        .frame(height: 180)
                    VStack(spacing: 8) {
                        Text(stateEmoji)
                            .font(.system(size: 70))
                        Text(stateLabel)
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
            .buttonStyle(.plain)

            // Indicador del transcript actual
            if !voice.lastTranscript.isEmpty {
                Text("\u{201C}\(voice.lastTranscript)\u{201D}")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var stateGradient: LinearGradient {
        switch voice.state {
        case .speaking:
            return LinearGradient(colors: [Color.green.opacity(0.4), Color.green.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .listening:
            return LinearGradient(colors: [Color.cyan.opacity(0.3), Color.cyan.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .translating:
            return LinearGradient(colors: [Color.yellow.opacity(0.4), Color.yellow.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .stopped:
            return LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var stateEmoji: String {
        switch voice.state {
        case .speaking: return "🔊"
        case .listening: return "👂"
        case .translating: return "🔄"
        case .stopped: return "⏸️"
        default: return "🎙️"
        }
    }

    private var stateLabel: String {
        switch voice.state {
        case .speaking: return "HABLANDO"
        case .listening: return "ESCUCHANDO"
        case .translating: return "TRADUCIENDO"
        case .stopped: return "REINICIAR"
        default: return "TOCÁ PARA EMPEZAR"
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("o escribí un comando...", text: $textInput)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(10)
                .submitLabel(.send)
                .onSubmit { handleTextSubmit() }
            Button(action: handleTextSubmit) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(textInput.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
            }
            .disabled(textInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func handleTextSubmit() {
        let q = textInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        let results = matcher.search(q)
        if let best = results.first {
            tts.speak("嗨伊娃", completion: {
                tts.speakCommand(best.command)
            })
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 6) {
                if !matcher.loaded {
                    HStack {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Cargando catálogo...")
                            .font(.caption).foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 20)
                } else if matcher.matches.isEmpty {
                    Text(voice.state == .stopped
                         ? "Tocá el micrófono para empezar a escuchar"
                         : matcher.lastQuery.isEmpty
                            ? "254 comandos listos. Decí tu comando en español o escribí abajo."
                            : "Sin coincidencias para \"\(matcher.lastQuery)\".")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal)
                } else {
                    ForEach(Array(matcher.matches.enumerated()), id: \.offset) { idx, m in
                        resultRow(m, isBest: idx == 0)
                    }
                }
            }
        }
    }

    private func resultRow(_ m: CatalogMatch, isBest: Bool) -> some View {
        Button {
            tts.speak("嗨伊娃", completion: {
                tts.speakCommand(m.command)
            })
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.command.es)
                    .font(.subheadline).foregroundColor(.white)
                Text(m.command.zh)
                    .font(.title3.weight(.medium))
                    .foregroundColor(isBest ? .green : .yellow)
                if let tags = m.command.tags, !tags.isEmpty {
                    Text(tags.joined(separator: " · "))
                        .font(.caption2).foregroundColor(.gray)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isBest ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isBest ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("Escucha continua · Decí \"adiós\" para detener · v2.1")
            .font(.caption2)
            .foregroundColor(.gray.opacity(0.6))
    }
}
