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

    /// Mapa de palabras numéricas en ESPAÑOL a su valor entero.
    /// Permite que el user diga "la uno", "la dos", etc. para elegir
    /// una opción de la lista de confirmación/sugerencias.
    private static let numberWordsEs: [String: Int] = [
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

    /// Mapa de palabras numéricas en INGLÉS a su valor entero.
    /// "one", "two", "three", "the first", "option two", "number 3", "1", etc.
    private static let numberWordsEn: [String: Int] = [
        // cardinal
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8,
        // ordinal
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
        "sixth": 6, "seventh": 7, "eighth": 8,
        // "the" + número
        "the 1": 1, "the 2": 2, "the 3": 3, "the 4": 4, "the 5": 5,
        "the 6": 6, "the 7": 7, "the 8": 8,
        // "option" + número
        "option 1": 1, "option 2": 2, "option 3": 3, "option 4": 4,
        "option 5": 5, "option 6": 6, "option 7": 7, "option 8": 8,
        // "number" + número
        "number 1": 1, "number 2": 2, "number 3": 3, "number 4": 4,
        "number 5": 5, "number 6": 6, "number 7": 7, "number 8": 8,
        // palabras coloquiales
        "the first": 1, "the second": 2, "the third": 3, "the fourth": 4,
        "the fifth": 5, "the sixth": 6, "the seventh": 7, "the eighth": 8,
    ]

    /// Mapa de palabras numéricas en RUSO a su valor entero.
    private static let numberWordsRu: [String: Int] = [
        // cardinal (один, два, три, ...)
        "один": 1, "два": 2, "три": 3, "четыре": 4, "пять": 5,
        "шесть": 6, "семь": 7, "восемь": 8,
        // "первый" (first), "второй" (second), etc. — masculino
        "первый": 1, "первая": 1, "первое": 1,
        "второй": 2, "вторая": 2, "второе": 2,
        "третий": 3, "третья": 3, "третье": 3,
        "четвёртый": 4, "четвертый": 4, "четвёртая": 4, "четвертая": 4,
        "пятый": 5, "пятая": 5,
        "шестой": 6, "шестая": 6,
        "седьмой": 7, "седьмая": 7,
        "восьмой": 8, "восьмая": 8,
    ]

    /// Intenta extraer un número 1-8 del transcript. Retorna nil si no
    /// detecta ninguno.
    /// Acepta: "uno", "la uno", "la 1", "primera", "número 3", "3" (español)
    ///         "one", "the first", "option 2", "number 3" (inglés)
    ///         "один", "первый", "два" (ruso)
    /// Si pasás un locale, prioriza las palabras de ese idioma.
    static func extractOptionNumber(_ transcript: String, locale: String = "es-MX") -> Int? {
        let normalized = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Para español, aplicamos diacritic-insensitive (la ñ, acentos)
        // Para en/ru, no hace falta (sus letras son ASCII o cirílicas)
        let isEs = locale.hasPrefix("es")
        let normalizedDiacritic = isEs
            ? normalized.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
            : normalized

        // Primero: número directo (1-8) como token (todos los idiomas lo soportan)
        let tokens = normalizedDiacritic.split(separator: " ").map(String.init)
        for token in tokens {
            if let n = Int(token), (1...8).contains(n) {
                return n
            }
        }

        // Segundo: palabras numéricas según locale del ASR
        let primaryDict: [String: Int]
        let fallbackDict: [String: Int]
        switch locale {
        case "en-US":
            primaryDict = numberWordsEn
            fallbackDict = numberWordsEs
        case "ru-RU":
            primaryDict = numberWordsRu
            fallbackDict = numberWordsEn
        default: // es-MX
            primaryDict = numberWordsEs
            fallbackDict = numberWordsEn
        }
        for (word, value) in primaryDict {
            if normalizedDiacritic.contains(word) {
                return value
            }
        }
        // Fallback: si no matcheó en el idioma del TTS, probar otros
        for (word, value) in fallbackDict {
            if normalizedDiacritic.contains(word) {
                return value
            }
        }

        // Tercero: prefijo + número (varía por idioma)
        for n in 1...8 {
            if isEs {
                if normalizedDiacritic.contains("la \(n)") || normalizedDiacritic.contains("el \(n)") {
                    return n
                }
            } else {
                if normalizedDiacritic.contains("the \(n)") || normalizedDiacritic.contains("number \(n)") {
                    return n
                }
            }
        }

        return nil
    }
}
