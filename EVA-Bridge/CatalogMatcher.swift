//
//  CatalogMatcher.swift
//  EVA Bridge
//
//  Carga el catálogo embebido de 254 comandos EVA (es→zh) y
//  hace búsqueda fuzzy con distancia de Levenshtein.
//

import Foundation
import Combine

// MARK: - Modelos

struct EvaCommand: Codable, Identifiable, Hashable {
    let id: String
    let es: String
    let zh: String
    let tags: [String]?
    let variants: [String]?
}

struct CatalogMatch: Identifiable {
    let id = UUID()
    let command: EvaCommand
    let score: Int
    /// Puntaje máximo posible para este comando (basado en la cantidad de tokens).
    /// Se usa para calcular `confidence` como un ratio 0-1.
    let maxScore: Int

    /// Confianza del match, de 0.0 a 1.0.
    /// - 1.0 = match perfecto (todos los tokens del comando matchearon exactamente)
    /// - 0.5-0.7 = match parcial con Levenshtein/contains
    /// - <0.3 = match pobre, no se debería ejecutar sin confirmación
    var confidence: Double {
        guard maxScore > 0 else { return 0 }
        return min(1.0, Double(score) / Double(maxScore))
    }

    /// Categoría semántica del comando, inferida del texto y los tags.
    /// Útil para la mejora #2: sugerir alternativas de la misma categoría.
    /// Devuelve un string en minúsculas y sin acentos (ej. "ventana", "cajuela", "musica").
    var category: String? {
        let haystack = (([command.es] + (command.variants ?? []) + (command.tags ?? [])).joined(separator: " ") + " " + (command.zh))
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
        // Tabla de keywords → categoría
        let map: [(String, [String])] = [
            ("ventana", ["ventana", "window", "ventanilla", "玻璃", "subir ventana", "bajar ventana"]),
            ("cajuela", ["cajuela", "maletero", "porton trasero", "trunk", "boot", "后备箱", "baul"]),
            ("puerta", ["puerta", "door", "车门"]),
            ("clima", ["aire", "clima", "aire acondicionado", "temperatura", "calefaccion", "ventilador", "fan", "ac"]),
            ("musica", ["musica", "musica", "cancion", "cantar", "reproducir", "play", "pause", "pausa", "siguiente", "anterior", "volumen", "audio", "radio", "spotify", "apple music", "音乐", "歌曲"]),
            ("luz", ["luz", "luces", "faro", "lampara", "灯光", "headlight"]),
            ("asiento", ["asiento", "seat", "座椅", "silla"]),
            ("navegacion", ["navegacion", "gps", "mapa", "destino", "导航", "地图", "ruta", "direccion"]),
            ("llamada", ["llamar", "llamada", "telefono", "电话", "contacto", "marcar"]),
            ("app", ["app", "aplicacion", "abrir aplicacion", "cerrar aplicacion", "应用"]),
            ("techo", ["techo solar", "sunroof", "天窗", "techo"]),
            ("espejo", ["espejo", "mirror", "后视镜"]),
            ("alarma", ["alarma", "seguridad", "bloquear", "desbloquear", "安全", "alerta", "bocina"]),
            ("info", ["informacion", "estado", "bateria", "autonomia", "信息", "里程", "consumo", "kilometraje"]),
        ]
        for (cat, keywords) in map {
            if keywords.contains(where: { haystack.contains($0) }) {
                return cat
            }
        }
        return nil
    }
}

// MARK: - Manager

@MainActor
final class CatalogMatcher: ObservableObject {
    @Published var commands: [EvaCommand] = []
    @Published var matches: [CatalogMatch] = []
    @Published var loaded: Bool = false
    @Published var error: String?
    @Published var lastQuery: String = ""

    init() {
        load()
    }

    /// Carga catalog.json desde el bundle.
    func load() {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else {
            self.error = "catalog.json no encontrado en el bundle"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let cmds = try JSONDecoder().decode([EvaCommand].self, from: data)
            self.commands = cmds
            self.loaded = true
        } catch {
            self.error = "Error cargando catálogo: \(error.localizedDescription)"
        }
    }

    /// Busca el query en el catálogo. Retorna top 8 resultados.
    func search(_ query: String) -> [CatalogMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastQuery = q
        guard !q.isEmpty else {
            self.matches = []
            return []
        }
        let qTokens = tokenize(q)
        guard !qTokens.isEmpty else {
            self.matches = []
            return []
        }

        var results: [CatalogMatch] = []
        for cmd in commands {
            let corpus = ([cmd.es] + (cmd.variants ?? []) + (cmd.tags ?? [])).joined(separator: " ")
            let cTokens = tokenize(corpus)
            // maxScore = cuántos tokens del comando matchearon perfectamente (10 puntos c/u)
            let maxScore = cTokens.count * 10
            var score = 0

            for qt in qTokens {
                var bestForToken = 0
                for ct in cTokens {
                    if ct == qt {
                        bestForToken = max(bestForToken, 10)
                    } else if ct.contains(qt) || qt.contains(ct) {
                        bestForToken = max(bestForToken, 5)
                    } else {
                        let d = levenshtein(qt, ct)
                        let maxLen = min(qt.count, ct.count)
                        let threshold = max(1, Int(Double(maxLen) * 0.3))
                        if d <= threshold {
                            bestForToken = max(bestForToken, 3)
                        }
                    }
                }
                score += bestForToken
            }

            if score > 0 {
                results.append(CatalogMatch(command: cmd, score: score, maxScore: maxScore))
            }
        }

        results.sort { $0.score > $1.score }
        let top = Array(results.prefix(8))
        self.matches = top
        return top
    }

    /// Busca comandos cuya categoría (inferida del texto+tags) coincida con
    /// alguna de las keywords provistas. Usado por la mejora #2 cuando el
    /// `search()` no encuentra match: devolvemos todas las opciones del tema
    /// que el user mencionó.
    ///
    /// Ejemplo: si el user dice "cajuela" y no hay match exacto, esta función
    /// devuelve todos los comandos cuya `category` sea "cajuela" (abrir maletero,
    /// cerrar maletero, etc.)
    func searchByCategory(_ query: String, maxResults: Int = 8) -> [EvaCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let qTokens = tokenize(q)
        guard !qTokens.isEmpty else { return [] }

        // Tabla de mapeo: token → categorías relacionadas.
        // Esto permite que el user diga "ventana" y devuelva comandos de
        // category=ventana aunque el comando diga "subir el cristal".
        let categoryKeywords: [String: [String]] = [
            "ventana": ["ventana", "ventanilla", "cristal"],
            "cajuela": ["cajuela", "maletero", "baul", "porton", "trunk"],
            "puerta": ["puerta", "portezuela"],
            "clima": ["aire", "clima", "temperatura", "calefaccion", "ventilador"],
            "musica": ["musica", "musica", "cancion", "audio", "radio", "volumen", "sonido"],
            "luz": ["luz", "luces", "faro", "lampara"],
            "asiento": ["asiento", "silla", "asientos"],
            "navegacion": ["navegacion", "gps", "mapa", "destino", "ruta", "direccion"],
            "llamada": ["llamar", "llamada", "telefono", "contacto", "marcar"],
            "app": ["app", "aplicacion"],
            "techo": ["techo", "sunroof"],
            "espejo": ["espejo"],
            "alarma": ["alarma", "seguridad", "bloquear", "desbloquear"],
            "info": ["informacion", "estado", "bateria", "autonomia", "consumo", "kilometraje"],
        ]

        // Encontrar categorías que matcheen los tokens del query
        var matchedCategories: Set<String> = []
        for token in qTokens {
            for (cat, keywords) in categoryKeywords {
                if keywords.contains(token) {
                    matchedCategories.insert(cat)
                }
            }
        }
        guard !matchedCategories.isEmpty else { return [] }

        // Filtrar comandos cuya category inferida esté en matchedCategories
        let results = commands.filter { cmd in
            let probe = CatalogMatch(command: cmd, score: 0, maxScore: 0)
            guard let cat = probe.category else { return false }
            return matchedCategories.contains(cat)
        }
        return Array(results.prefix(maxResults))
    }

    // MARK: - Util

    /// Normaliza texto: lowercase, sin acentos, sin puntuación, tokenizado.
    private func tokenize(_ s: String) -> [String] {
        let lowered = s.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
        var result: [String] = []
        lowered.enumerateSubstrings(in: lowered.startIndex..<lowered.endIndex,
                                    options: [.byWords, .localized]) { substring, _, _, _ in
            if let s = substring, s.count > 1 {
                result.append(s)
            }
        }
        return result
    }

    /// Distancia de Levenshtein (DP).
    private func levenshtein(_ a: String, _ b: String) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        if a == b { return 0 }
        let aChars = Array(a), bChars = Array(b)
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
