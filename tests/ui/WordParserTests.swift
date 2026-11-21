import XCTest
@testable import equmaczer

final class WordParserTests: XCTestCase {
    private func moves(_ text: String) -> [(Double, Float)] {
        WordParser.parse(text).moves.map { ($0.frequency, $0.deltaDB) }
    }

    func testParsingTable() {
        let table: [(String, [(Double, Float)])] = [
            ("warmer", [(250, 2)]),
            ("Thinner", [(120, -2)]),
            ("punchier", [(60, 2)]),
            ("cosy", [(250, 2)]),                       // synonym
            ("crisper", [(3000, 1.5)]),                 // synonym
            ("a bit brighter", [(8000, 1)]),            // gentle ×0.5
            ("slightly darker", [(8000, -1)]),
            ("much warmer", [(250, 4)]),                // strong ×2
            ("a lot clearer", [(3000, 3)]),
            ("boomy", [(100, -2)]),                     // bare complaint settles
            ("less boomy", [(100, -2)]),
            ("more boomy", [(100, 2)]),
            ("a bit less muddy", [(250, -1)]),
            ("less warm", [(250, -2)]),
        ]
        for (text, expected) in table {
            let actual = moves(text)
            XCTAssertEqual(actual.count, expected.count, text)
            for (a, e) in zip(actual, expected) {
                XCTAssertEqual(a.0, e.0, text)
                XCTAssertEqual(a.1, e.1, accuracy: 0.001, text)
            }
        }
    }

    func testCombinationsKeepEachClauseSeparate() {
        let warmerLessBoomy = WordParser.parse("warmer but less boomy")
        XCTAssertEqual(warmerLessBoomy.moves.map(\.frequency), [250, 100])
        XCTAssertEqual(warmerLessBoomy.moves.map(\.deltaDB), [2, -2])
        let mixed = WordParser.parse("a bit brighter, much less harsh and warmer")
        XCTAssertEqual(mixed.moves.map(\.frequency), [8000, 3500, 250])
        XCTAssertEqual(mixed.moves[0].deltaDB, 1, accuracy: 0.001)   // a bit: ×0.5
        XCTAssertEqual(mixed.moves[1].deltaDB, -4, accuracy: 0.001)  // much less: 2 × −2
        XCTAssertEqual(mixed.moves[2].deltaDB, 2, accuracy: 0.001)   // modifiers do not leak across clauses
    }

    func testUnknownWordGivesReceiptAndNoMoves() {
        let plan = WordParser.parse("warmer but sparkly")
        XCTAssertEqual(plan.unknownWord, "sparkly")
        XCTAssertTrue(plan.moves.isEmpty, "Nothing is applied when any word is unknown")
    }

    func testDanglingModifierProposesNothing() {
        XCTAssertEqual(WordParser.parse("less").danglingModifier, "less")
        XCTAssertEqual(WordParser.parse("warmer but a bit").danglingModifier, "bit")
        XCTAssertTrue(WordParser.parse("warmer but less").moves.isEmpty)
    }

    func testEmptyTextIsNothing() {
        XCTAssertEqual(WordParser.parse("   "), WordPlan())
    }

    func testEveryVocabularyWordHasADocumentedMove() {
        for (word, trait) in WordParser.traits {
            XCTAssertFalse(trait.area.isEmpty, word)
            XCTAssertNotEqual(trait.delta, 0, word)
            XCTAssertTrue((20...20_000).contains(trait.frequency), word)
        }
    }

    func testReceiptEffectWordsFollowTheSign() {
        XCTAssertEqual(WordParser.parse("warmer").moves[0].effect, "lifts the low warmth")
        XCTAssertEqual(WordParser.parse("less boomy").moves[0].effect, "settles the boom")
    }
}
