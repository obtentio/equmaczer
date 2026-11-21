// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// One documented curve move: raise or lower the band nearest
/// `frequency` by `deltaDB`.
struct WordMove: Equatable {
    let phrase: String
    let frequency: Double
    let deltaDB: Float
    let area: String

    var effect: String { "\(deltaDB >= 0 ? "lifts" : "settles") the \(area)" }
}

/// What a typed phrase means. Unknown words never produce moves.
struct WordPlan: Equatable {
    var moves: [WordMove] = []
    /// The first word that is not in the vocabulary; when set,
    /// nothing is applied.
    var unknownWord: String?
    /// A dangling modifier ("less" with nothing after it).
    var danglingModifier: String?
}

/// The vocabulary behind the describe… field, and its phrase parser.
/// Pure: no I/O, no EQ state.
///
/// Grammar: a phrase is words; conjunctions ("but", "and", "then",
/// "while", commas) start a new clause. A clause is optional
/// intensity words, an optional direction word, then a trait word.
///
/// Documented curve moves — "more" of each trait, in dB at the
/// nearest band to the frequency (each move is clamped to ±18 dB
/// per band by the caller):
///
/// | trait (and synonyms)            | Hz    | more | bare word means |
/// |---------------------------------|-------|------|-----------------|
/// | warm / warmer / cosy            | 250   | +2.0 | more            |
/// | full / fuller / rich / richer   | 120   | +2.0 | more            |
/// | thinner / thin                  | 120   | −2.0 | more            |
/// | bright / brighter               | 8000  | +2.0 | more            |
/// | airy / airier                   | 10000 | +2.0 | more            |
/// | dark / darker / dull / duller   | 8000  | −2.0 | more            |
/// | clear / clearer / crisp / crisper | 3000 | +1.5 | more           |
/// | soft / softer / gentle / gentler | 3000 | −1.5 | more            |
/// | punchy / punchier               | 60    | +2.0 | more            |
/// | bassy / bassier                 | 80    | +2.0 | more            |
/// | boomy                           | 100   | +2.0 | less (complaint)|
/// | muddy                           | 250   | +2.0 | less (complaint)|
/// | boxy                            | 500   | +2.0 | less (complaint)|
/// | nasal                           | 1000  | +2.0 | less (complaint)|
/// | harsh                           | 3500  | +2.0 | less (complaint)|
/// | sharp / sibilant                | 7000  | +2.0 | less (complaint)|
///
/// For a complaint word the table's delta is what *more* of the
/// trait would do, so "boomy" and "less boomy" both settle 100 Hz,
/// and "more boomy" lifts it.
///
/// Intensity: "a bit", "slightly", "a little", "a touch" ×0.5;
/// "much", "a lot", "way", "far", "very", "really" ×2.
/// Direction: "more" ×+1, "less", "fewer", "reduce", "lower" ×−1.
enum WordParser {
    struct Trait {
        let area: String
        let frequency: Double
        /// What "more" of the trait does, dB.
        let delta: Float
        /// Whether the bare word asks for less of it ("boomy").
        let bareMeansLess: Bool
    }

    static let traits: [String: Trait] = {
        var table: [String: Trait] = [:]
        func add(_ words: [String], _ area: String, _ frequency: Double, _ delta: Float, complaint: Bool = false) {
            let trait = Trait(area: area, frequency: frequency, delta: delta, bareMeansLess: complaint)
            for word in words { table[word] = trait }
        }
        add(["warm", "warmer", "cosy", "cosier"], "low warmth", 250, 2)
        add(["full", "fuller", "rich", "richer"], "body", 120, 2)
        add(["thin", "thinner"], "body", 120, -2)
        add(["bright", "brighter"], "top", 8000, 2)
        add(["airy", "airier"], "air", 10_000, 2)
        add(["dark", "darker", "dull", "duller"], "top", 8000, -2)
        add(["clear", "clearer", "crisp", "crisper"], "presence", 3000, 1.5)
        add(["soft", "softer", "gentle", "gentler"], "presence", 3000, -1.5)
        add(["punchy", "punchier"], "punch", 60, 2)
        add(["bassy", "bassier"], "bass", 80, 2)
        add(["boomy"], "boom", 100, 2, complaint: true)
        add(["muddy"], "mud", 250, 2, complaint: true)
        add(["boxy"], "box", 500, 2, complaint: true)
        add(["nasal"], "nasal mids", 1000, 2, complaint: true)
        add(["harsh"], "harshness", 3500, 2, complaint: true)
        add(["sharp", "sibilant"], "sibilance", 7000, 2, complaint: true)
        return table
    }()

    private static let gentle: Set<String> = ["bit", "slightly", "little", "touch", "tad", "somewhat"]
    private static let strong: Set<String> = ["much", "lot", "lots", "way", "far", "very", "really"]
    private static let more: Set<String> = ["more"]
    private static let less: Set<String> = ["less", "fewer", "reduce", "lower"]
    private static let fillers: Set<String> = ["a", "an", "the", "it", "sound", "make", "please", "just", "too", "so"]
    private static let conjunctions: Set<String> = ["but", "and", "then", "while", "also", "yet", "though"]

    /// The words as typed, lowercased, split on non-alphanumerics.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func isKnown(_ word: String) -> Bool {
        traits[word] != nil || gentle.contains(word) || strong.contains(word)
            || more.contains(word) || less.contains(word)
            || fillers.contains(word) || conjunctions.contains(word)
    }

    static func parse(_ text: String) -> WordPlan {
        let words = tokens(text)
        var plan = WordPlan()
        if let unknown = words.first(where: { !isKnown($0) }) {
            plan.unknownWord = unknown
            return plan
        }
        var scale: Float = 1
        var direction: Float?
        var phrase: [String] = []
        func resetClause() { scale = 1; direction = nil; phrase = [] }
        for word in words {
            if conjunctions.contains(word) {
                if let loose = phrase.last { plan.danglingModifier = loose }
                resetClause()
            } else if gentle.contains(word) {
                scale *= 0.5; phrase.append(word)
            } else if strong.contains(word) {
                scale *= 2; phrase.append(word)
            } else if more.contains(word) {
                direction = 1; phrase.append(word)
            } else if less.contains(word) {
                direction = -1; phrase.append(word)
            } else if let trait = traits[word] {
                let sense = direction ?? (trait.bareMeansLess ? -1 : 1)
                plan.moves.append(WordMove(
                    phrase: (phrase + [word]).joined(separator: " "),
                    frequency: trait.frequency,
                    deltaDB: trait.delta * sense * scale,
                    area: trait.area
                ))
                resetClause()
            }
        }
        if let loose = phrase.last { plan.danglingModifier = loose }
        if plan.danglingModifier != nil { plan.moves = [] }
        return plan
    }
}
