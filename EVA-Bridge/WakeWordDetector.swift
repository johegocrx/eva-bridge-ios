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

    // MARK: - Selección por número de opción

    /// Mapa de palabras numéricas en español a su valor entero.
    /// Permite que el user diga "la uno", "la dos", etc. para elegir
    /// una opción de la lista de confirmación/sugerencias.
    private static let numberWords: [String: Int] = [
        "uno": 1, "primera": 1, "primero": 1,
        "dos": 2, "segunda": 2, "segundo": 2,
        "tres": 3, "tercera": 3, "tercero": 3,
        "cuatro": 4, "cuarta": 4, "cuarto": 4,
        "cinco": 5, "quinta": 5, "quinto": 5,
        "seis": 6, "sexta": 6, "sexto": 6,
        "siete": 7, "séptima": 7, "septima": 7, "séptimo": 7, "septimo": 7,
        "ocho": 8, "octava": 8, "octavo": 8,
        "la 1": 1, "la 2": 2, "la 3": 3, "la 4": 4, "la 5": 5,
        "la 6": 6, "la 7": 7, "la 8": 8,
        "el 1": 1, "el 2": 2, "el 3": 3, "el 4": 4, "el 5": 5,
        "el 6": 6, "el 7": 7, "el 8": 8,
        "número 1": 1, "número 2": 2, "número 3": 3, "número 4": 4, "número 5": 5,
        "numero 1": 1, "numero 2": 2, "numero 3": 3, "numero 4": 4, "numero 5": 5,
    ]

    /// Intenta extraer un número 1-8 del transcript. Retorna nil si no
    /// detecta ninguno.
    /// Acepta: "uno", "la uno", "la 1", "primera", "número 3", "3", etc.
    static func extractOptionNumber(_ transcript: String) -> Int? {
        let normalized = transcript
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Primero: número directo (1-8) como token
        let tokens = normalized.split(separator: " ").map(String.init)
        for token in tokens {
            if let n = Int(token), (1...8).contains(n) {
                return n
            }
        }

        // Segundo: palabras numéricas completas
        for (word, value) in numberWords {
            if normalized.contains(word) {
                return value
            }
        }

        // Tercero: prefijo "la " o "el " + número como substring
        for n in 1...8 {
            if normalized.contains("la \(n)") || normalized.contains("el \(n)") {
                return n
            }
        }

        return nil
    }
}
