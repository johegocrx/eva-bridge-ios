//
//  CommandHistory.swift
//  Eva Copilot
//
//  Historial de los últimos N comandos ejecutados, con timestamp y resultado.
//  Persistido en UserDefaults (JSON) para que sobreviva entre sesiones.
//

import Foundation
import Combine

@MainActor
final class CommandHistory: ObservableObject {

    struct HistoryEntry: Codable, Identifiable, Hashable {
        let id: UUID
        let timestamp: Date
        let inputEs: String        // Lo que el ASR transcribió (español)
        let commandEs: String      // El comando del catálogo que se ejecutó
        let commandZh: String      // Lo que se le pasó a EVA en chino
        let confidence: Double     // 0-1
        let wasConfirmed: Bool     // true si pasó por modo seguro
        let category: String?      // categoría inferida (ventana, cajuela, etc.)
    }

    @Published var entries: [HistoryEntry] = []
    private let maxEntries = 20
    private let storageKey = "eva_copilot_command_history"

    init() {
        load()
    }

    /// Agrega una entrada al historial. Se mantiene solo las últimas N.
    func add(
        inputEs: String,
        command: EvaCommand,
        confidence: Double,
        wasConfirmed: Bool
    ) {
        let category = CatalogMatch(command: command, score: 0, maxScore: 0).category
        let entry = HistoryEntry(
            id: UUID(),
            timestamp: Date(),
            inputEs: inputEs,
            commandEs: command.es,
            commandZh: command.zh,
            confidence: confidence,
            wasConfirmed: wasConfirmed,
            category: category
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    /// Borra todo el historial.
    func clear() {
        entries = []
        save()
    }

    /// Repite un comando del historial (lo vuelve a hablar a EVA).
    /// Devuelve el comando para que el caller lo ejecute con el TTS.
    func repeatEntry(_ entry: HistoryEntry) -> (es: String, zh: String)? {
        guard let cmd = entries.first(where: { $0.id == entry.id }) else { return nil }
        return (cmd.commandEs, cmd.commandZh)
    }

    // MARK: - Persistencia

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Silenciar: no es crítico
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return
        }
        entries = loaded
    }
}
