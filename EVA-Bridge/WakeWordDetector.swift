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

    /// Comandos para cancelar la confirmación pendiente (modo seguro).
    /// Distintos de stop porque NO detienen la escucha, solo descartan la sugerencia.
    static let cancelCommands: [String] = [
        "cancelar", "no", "nada", "ninguno", "ninguna", "incorrecto",
        "esa no", "esa no es", "mal", "equivocado", "error", "siguiente"
    ]

    /// Determina si el transcript contiene un comando de stop.
    static func isStopCommand(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stopCommands.contains { normalized.contains($0) }
    }

    /// Determina si el transcript es un comando para cancelar la confirmación
    /// pendiente del modo seguro.
    static func isCancelCommand(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cancelCommands.contains { normalized.contains($0) }
    }

    /// Comandos para reanudar la escucha continua después de un stop.
    static let startCommands: [String] = [
        "oye yoe", "oye yo", "escuchar", "empezar", "iniciar",
        "reanudar", "continuar", "seguir", "listo", "继续"
    ]

    /// Determina si el transcript es un comando para iniciar/reanudar la escucha.
    static func isStartCommand(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return startCommands.contains { normalized.contains($0) }
    }
}
