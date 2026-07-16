//
//  WakeWordDetector.swift
//  Eva Copilot - Yoe wake word detection
//
//  Detecta si un transcript contiene una variante del wake word "Yoe".
//

import Foundation

struct WakeWordDetector {
    /// Variantes aceptadas del wake word (todas mapean a "Yoe")
    /// Incluimos las 6 formas que el usuario puede decir:
    ///   - "Hola Yoe" / "Ola Yoe" (sin H)
    ///   - "Oye Yoe"
    ///   - "Yoe" (solo)
    ///   - "Ey Yoe" / "Hey Yoe"
    ///   - "Buenas Yoe"
    static let variants: [String] = [
        "hola yoe", "ola yoe", "oye yoe", "yoe", "ey yoe", "hey yoe", "buenas yoe"
    ]

    /// Determina si el transcript contiene el wake word.
    /// - Parameter transcript: el texto reconocido por el recognizer
    /// - Returns: true si el wake word fue detectado
    static func containsWakeWord(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for variant in variants {
            if normalized.contains(variant) { return true }
        }
        return false
    }

    /// Extrae el comando del transcript quitando el wake word.
    /// Ej: "Hola Yoe enciende el clima" → "enciende el clima"
    static func extractCommand(from transcript: String) -> String {
        var s = transcript
        for variant in variants {
            s = s.replacingOccurrences(of: variant, with: "", options: [.caseInsensitive, .diacriticInsensitive])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Comandos para detener la escucha continua
    static let stopCommands: [String] = [
        "adiós", "adios", "cancelar", "para", "stop", "salir", "terminar", "chao", "chau"
    ]

    static func isStopCommand(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stopCommands.contains { normalized.contains($0) }
    }
}