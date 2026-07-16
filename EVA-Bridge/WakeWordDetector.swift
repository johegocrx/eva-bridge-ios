//
//  WakeWordDetector.swift
//  Eva Copilot
//
//  Detecta comandos de stop (para detener la escucha continua).
//  Ya no se usa wake word en español: la app traduce todo lo que escucha.
//

import Foundation

struct WakeWordDetector {

    /// Comandos que el usuario puede decir para detener la escucha continua
    /// y que la app deje de hablar a EVA.
    static let stopCommands: [String] = [
        "adiós", "adios", "cancelar", "para", "stop",
        "salir", "terminar", "chao", "chau",
        "silencio", "cállate", "callate", "basta", "ya"
    ]

    /// Determina si el transcript contiene un comando de stop.
    static func isStopCommand(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stopCommands.contains { normalized.contains($0) }
    }
}
