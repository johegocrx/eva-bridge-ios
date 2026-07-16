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
                results.append(CatalogMatch(command: cmd, score: score))
            }
        }

        results.sort { $0.score > $1.score }
        let top = Array(results.prefix(8))
        self.matches = top
        return top
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
