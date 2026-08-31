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
    /// Traducción al inglés (mejora #4: multi-idioma). Opcional.
    let en: String?
    /// Traducción al ruso (mejora #4: multi-idioma). Opcional.
    let ru: String?
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
            // Corpus = todos los textos en todos los idiomas disponibles.
            // Mejora #4: incluye en/ru para matchear input en otros idiomas.
            var corpusParts: [String] = [cmd.es]
            corpusParts.append(contentsOf: cmd.variants ?? [])
            corpusParts.append(contentsOf: cmd.tags ?? [])
            if let en = cmd.en { corpusParts.append(en) }
            if let ru = cmd.ru { corpusParts.append(ru) }
            let corpus = corpusParts.joined(separator: " ")
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
        let prelimTop = Array(results.prefix(12))
        // Mejora v2.4: re-rank considerando verbo+objeto. Esto evita que
        // "abrir ventana" termine mostrando "abrir puerto de carga" como
        // primera opción porque comparten el verbo pero NO el objeto.
        let top = reRankByIntent(prelimTop, query: q)
        self.matches = top
        return top
    }

    /// Re-rank los top matches considerando INTENCIÓN del user (verbo + objeto).
    ///
    /// Problema que arregla: si el user dice "abrir ventana", el algoritmo de
    /// scoring puede dar score alto a "abrir puerta", "abrir techo", "abrir
    /// guantera", etc. porque todos comparten el verbo "abrir". Pero el
    /// objeto "ventana" debería ser el discriminante.
    ///
    /// Estrategia:
    /// 1. Detectar si el query tiene un verbo de acción (abrir, cerrar, etc.)
    /// 2. Detectar si el query tiene un objeto clave (ventana, puerta, etc.)
    /// 3. Dar bonus si el comando matchea TANTO el verbo COMO el objeto
    /// 4. Penalizar comandos que solo matchean el verbo sin el objeto
    private func reRankByIntent(_ results: [CatalogMatch], query: String) -> [CatalogMatch] {
        guard !results.isEmpty else { return results }
        let qTokens = Set(tokenize(query))
        let hasVerb = !qTokens.intersection(actionVerbs).isEmpty
        // Mapear cada token del query a su categoría semántica (si la tiene)
        var queryObjects: Set<String> = []
        for token in qTokens {
            if let cat = objectToCategory[token] {
                queryObjects.insert(cat)
            }
        }
        // Si el query no tiene ni verbo ni objeto claro, no re-rankear
        guard hasVerb || !queryObjects.isEmpty else { return results }

        let reRanked: [CatalogMatch] = results.map { match in
            var bonus = 0
            let cmdLower = (match.command.es + " " + (match.command.variants?.joined(separator: " ") ?? "") + " " + (match.command.tags?.joined(separator: " ") ?? ""))
                .lowercased()
            let cmdTokens = Set(tokenize(cmdLower))

            // (1) Bonus por match del verbo
            if hasVerb {
                let cmdHasVerb = !cmdTokens.intersection(actionVerbs).isEmpty
                if cmdHasVerb {
                    bonus += 12
                } else {
                    // Penalizar: el query pidió un verbo claro y el comando
                    // no tiene ninguno. Probablemente es la categoría
                    // equivocada.
                    bonus -= 10
                }
            }

            // (2) Bonus por match del objeto (vía category inferida)
            for qObj in queryObjects {
                if let cat = match.category, cat == qObj {
                    // BIG bonus: el query pidió X objeto, y el comando es de X categoría
                    bonus += 25
                } else if cmdLower.contains(qObj) {
                    // Bonus chico: el objeto aparece como keyword en el comando
                    bonus += 8
                } else {
                    // Penalizar: el query pidió un objeto claro, el comando es de otra categoría
                    bonus -= 15
                }
            }

            let newScore = max(0, match.score + bonus)
            return CatalogMatch(command: match.command, score: newScore, maxScore: match.maxScore)
        }
        return reRanked.sorted { $0.score > $1.score }
    }

    /// Verbos de acción que típicamente el user combina con un objeto.
    /// Si el query tiene uno de estos, el comando ideal también debería
    /// tener uno (en cualquier conjugación).
    private let actionVerbs: Set<String> = [
        // abrir
        "abrir", "abre", "abreme", "abrirlo", "abrirla",
        // cerrar
        "cerrar", "cierra", "cierreme", "cerrarlo", "cerrarla",
        // encender
        "encender", "enciende", "enciendeme", "encenderlo", "encenderla",
        // apagar
        "apagar", "apaga", "apagame", "apagarlo", "apagarla",
        // prender
        "prender", "prende", "prendeme", "prenderlo", "prenderla",
        // subir
        "subir", "sube", "subeme", "subirlo", "subirla",
        // bajar
        "bajar", "baja", "bajame", "bajarlo", "bajarla",
        // bloquear
        "bloquear", "bloquea", "bloquearlo", "bloquearla",
        // desbloquear
        "desbloquear", "desbloquea", "desbloquearlo", "desbloquearla",
        // activar / desactivar
        "activar", "activa", "desactivar", "desactiva",
        // poner / quitar
        "poner", "pon", "quitar", "quita",
        // imperativos coloquiales
        "abreme", "cierra", "enciende", "apaga", "sube", "baja", "prende",
    ]

    /// Mapea cada palabra-objeto del query a la categoría semántica que
    /// debería tener el comando correcto. Si el user dice "ventana", el
    /// comando ideal es uno de categoría "ventana".
    private let objectToCategory: [String: String] = [
        // ventana
        "ventana": "ventana", "ventanilla": "ventana", "cristal": "ventana",
        "ventanas": "ventana", "cristales": "ventana",
        // puerta
        "puerta": "puerta", "portezuela": "puerta", "puertas": "puerta",
        // cajuela / maletero
        "cajuela": "cajuela", "maletero": "cajuela", "baul": "cajuela",
        "porton": "cajuela", "cofre": "cajuela",
        // techo
        "techo": "techo", "sunroof": "techo", "cortinazo": "techo",
        // luz
        "luz": "luz", "luces": "luz", "faro": "luz", "lampara": "luz",
        "luz": "luz",
        // música / audio
        "musica": "musica", "cancion": "musica", "audio": "musica",
        "radio": "musica", "volumen": "musica", "sonido": "musica",
        "spotify": "musica", "altavoz": "musica",
        // clima
        "clima": "clima", "aire": "clima", "temperatura": "clima",
        "calefaccion": "clima", "ventilador": "clima", "ac": "clima",
        // asiento
        "asiento": "asiento", "silla": "asiento", "asientos": "asiento",
        // espejo
        "espejo": "espejo", "espejos": "espejo",
        // guantera
        "guantera": "guantera",
        // apps específicas (separadas de la categoría genérica "app")
        "spotify": "musica", "waze": "navegacion", "youtube": "app",
        "netflix": "app", "bilibili": "app", "iqiyi": "app",
    ]

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
