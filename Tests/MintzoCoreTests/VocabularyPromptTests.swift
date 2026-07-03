import XCTest
@testable import MintzoCore

/// Construction de l'amorce whisper (`initial_prompt`) depuis les mots du dictionnaire.
final class VocabularyPromptTests: XCTestCase {

    func testJoinsWordsWithCommaAndFinalPeriod() {
        XCTAssertEqual(
            VocabularyPrompt.whisperPrompt(words: ["Bitwip", "Maite", "Donostia"]),
            "Bitwip, Maite, Donostia."
        )
    }

    func testSingleWord() {
        XCTAssertEqual(VocabularyPrompt.whisperPrompt(words: ["Bitwip"]), "Bitwip.")
    }

    func testEmptyAndBlankWordsYieldNil() {
        XCTAssertNil(VocabularyPrompt.whisperPrompt(words: []))
        XCTAssertNil(VocabularyPrompt.whisperPrompt(words: ["", "   "]))
    }

    func testBlankEntriesAreSkippedNotJoined() {
        XCTAssertEqual(
            VocabularyPrompt.whisperPrompt(words: ["Bitwip", " ", "Maite"]),
            "Bitwip, Maite."
        )
    }

    func testTruncatesToWholeWordsUnderLimit() throws {
        // 200 mots de 11 caractères ≈ 2 600 caractères joints : la limite de
        // 800 doit couper par mots entiers, en gardant le préfixe de la liste.
        let words = (0..<200).map { String(format: "Hitzalde%03d", $0) } // 11 chars
        let prompt = VocabularyPrompt.whisperPrompt(words: words)

        let unwrapped = try XCTUnwrap(prompt)
        XCTAssertLessThanOrEqual(unwrapped.count, VocabularyPrompt.maxLength)
        XCTAssertTrue(unwrapped.hasSuffix("."))
        XCTAssertTrue(unwrapped.hasPrefix("Hitzalde000, Hitzalde001"), "Ordre de la liste préservé")
        // Aucun mot coupé : chaque segment doit être un mot complet de la liste.
        let segments = unwrapped.dropLast().components(separatedBy: ", ")
        XCTAssertEqual(segments, Array(words.prefix(segments.count)),
                       "Troncature par mots ENTIERS uniquement")
        XCTAssertLessThan(segments.count, words.count, "La liste a bien été tronquée")
    }

    func testCustomLimitDropsWordThatWouldOverflow() {
        // "Bitwip, Maite." = 14 caractères ; limite 13 → « Maite » abandonné.
        XCTAssertEqual(
            VocabularyPrompt.whisperPrompt(words: ["Bitwip", "Maite"], limit: 13),
            "Bitwip."
        )
        // Limite trop courte même pour le premier mot → nil.
        XCTAssertNil(VocabularyPrompt.whisperPrompt(words: ["Interlokutorea"], limit: 5))
    }
}
