// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// One action in the Cmd+K palette (C4). Facets mark the three
/// composable kinds — a preset, an output device, a channel —
/// whose names a single query can combine into one composite
/// action ("AirPods + Film + Night").
struct PaletteAction {
    enum Facet: Equatable {
        case preset(String)
        case device(String)
        case channel(String)

        var value: String {
            switch self {
            case .preset(let name), .device(let name), .channel(let name):
                return name
            }
        }

        var kindOrder: Int {
            switch self {
            case .device: return 0
            case .channel: return 1
            case .preset: return 2
            }
        }
    }

    let id: String
    let title: String
    let detail: String?
    let facet: Facet?
    let keywords: [String]
    let execute: () -> Void

    init(
        id: String, title: String, detail: String? = nil,
        facet: Facet? = nil, keywords: [String] = [],
        execute: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.facet = facet
        self.keywords = keywords
        self.execute = execute
    }
}

/// Token matching over the palette catalogue, plus composite
/// synthesis. Pure: the view builds the catalogue from live
/// state, this type only decides what a query means.
struct PaletteIndex {
    let actions: [PaletteAction]

    static func tokens(of query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "apply" }
    }

    func results(for query: String, limit: Int = 8) -> [PaletteAction] {
        let tokens = Self.tokens(of: query)
        guard !tokens.isEmpty else { return Array(actions.prefix(limit)) }

        var ranked: [PaletteAction] = []
        if let composite = compositeAction(for: tokens) {
            ranked.append(composite)
        }
        let plain = actions.filter { action in
            let haystack = (action.title + " " + action.keywords.joined(separator: " ")).lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
        // Prefix hits on the title rank above deep substring hits.
        let prefixFirst = plain.filter { $0.title.lowercased().contains(tokens[0]) }
        let rest = plain.filter { !$0.title.lowercased().contains(tokens[0]) }
        ranked.append(contentsOf: prefixFirst + rest)
        return Array(ranked.prefix(limit))
    }

    /// When the query's tokens name values in two or more facet
    /// kinds, the composite applies them all — device, then
    /// channel, then preset. Every token must be consumed by a
    /// chosen facet value, or the query means something else and
    /// no composite is offered.
    private func compositeAction(for tokens: [String]) -> PaletteAction? {
        var chosen: [PaletteAction] = []
        var consumed = Set<String>()
        for kind in [0, 1, 2] { // device, channel, preset
            let candidates = actions.filter { $0.facet?.kindOrder == kind }
            var best: (action: PaletteAction, hits: [String])?
            for candidate in candidates {
                let value = candidate.facet?.value.lowercased() ?? ""
                let hits = tokens.filter { value.contains($0) }
                if hits.count > (best?.hits.count ?? 0) {
                    best = (candidate, hits)
                }
            }
            if let best, !best.hits.isEmpty {
                chosen.append(best.action)
                consumed.formUnion(best.hits)
            }
        }
        guard chosen.count >= 2, consumed.count == tokens.count else { return nil }
        let ordered = chosen.sorted { ($0.facet?.kindOrder ?? 0) < ($1.facet?.kindOrder ?? 0) }
        let names = ordered.map { $0.facet?.value ?? $0.title }
        return PaletteAction(
            id: "composite",
            title: "Apply — \(names.joined(separator: " · "))",
            detail: "all at once",
            execute: { ordered.forEach { $0.execute() } }
        )
    }
}
