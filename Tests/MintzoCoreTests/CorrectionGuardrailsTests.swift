import XCTest
@testable import MintzoCore

final class CorrectionGuardrailsTests: XCTestCase {

    // MARK: - evaluate : ratio de longueur

    func testOverlongOutputRejected() {
        let input = "kaixo maite bihar goizean elkartuko gara"
        let output = input + " " + String(repeating: "eta abar luze bat gehitu du modeloak ", count: 4)
        XCTAssertEqual(CorrectionGuardrails.evaluate(input: input, output: output), .lengthRatio)
    }

    func testTruncatedOutputRejected() {
        let input = "kaixo maite bihar goizean elkartuko gara bulegoan proiektua ixteko ados"
        let output = "Kaixo."
        XCTAssertEqual(CorrectionGuardrails.evaluate(input: input, output: output), .lengthRatio)
    }

    // MARK: - evaluate : identité et corrections légitimes

    func testIdenticalOutputAccepted() {
        let input = "bonjour on se retrouve demain matin au bureau"
        XCTAssertNil(CorrectionGuardrails.evaluate(input: input, output: input))
    }

    func testPunctuationAndCaseCorrectionAccepted() {
        let input = "kaixo maite bihar goizean elkartuko gara bulegoan proiektua ixteko ados"
        let output = "Kaixo, Maite! Bihar goizean elkartuko gara bulegoan, proiektua ixteko. Ados?"
        XCTAssertNil(
            CorrectionGuardrails.evaluate(input: input, output: output),
            "Ponctuation + majuscules ne doivent PAS compter comme des éditions de mots"
        )
    }

    func testRewrittenOutputRejected() {
        let input = "bonjour on se retrouve demain matin au bureau pour finir le projet"
        // Le modèle a « répondu » au lieu de corriger — mots presque tous différents.
        let output = "Très bien, je note votre rendez-vous et je vous souhaite une bonne journée"
        XCTAssertEqual(CorrectionGuardrails.evaluate(input: input, output: output), .lowSimilarity)
    }

    func testEmptyOutputRejected() {
        XCTAssertEqual(CorrectionGuardrails.evaluate(input: "kaixo", output: ""), .emptyOutput)
    }

    // MARK: - sanitize : méta-texte parasite

    func testFrenchMetaPrefixStripped() {
        let raw = "Voici le texte corrigé : Bonjour, on se retrouve demain."
        XCTAssertEqual(CorrectionGuardrails.sanitize(raw), "Bonjour, on se retrouve demain.")
    }

    func testBasqueMetaPrefixStripped() {
        let raw = "Testu zuzendua: Kaixo, Maite! Bihar elkartuko gara."
        XCTAssertEqual(CorrectionGuardrails.sanitize(raw), "Kaixo, Maite! Bihar elkartuko gara.")
    }

    func testWrappingQuotesStripped() {
        XCTAssertEqual(CorrectionGuardrails.sanitize("« Kaixo, Maite! »"), "Kaixo, Maite!")
        XCTAssertEqual(CorrectionGuardrails.sanitize("\"Bonjour, Maite.\""), "Bonjour, Maite.")
    }

    func testCleanOutputUntouched() {
        let clean = "Kaixo, Maite! Bihar goizean elkartuko gara."
        XCTAssertEqual(CorrectionGuardrails.sanitize(clean), clean)
    }

    func testWhitespaceOnlyOutputSanitizesToEmpty() {
        XCTAssertEqual(CorrectionGuardrails.sanitize("  \n\t "), "")
    }

    // MARK: - wordSimilarity

    func testWordSimilarityIdenticalIsOne() {
        XCTAssertEqual(CorrectionGuardrails.wordSimilarity("kaixo maite", "Kaixo, Maite!"), 1.0)
    }

    func testWordSimilarityDisjointIsZero() {
        XCTAssertEqual(CorrectionGuardrails.wordSimilarity("aaa bbb ccc", "xxx yyy zzz"), 0.0)
    }

    func testWordSimilaritySingleSubstitution() {
        // 1 mot remplacé sur 4 → similarité 0,75.
        XCTAssertEqual(
            CorrectionGuardrails.wordSimilarity("un deux trois quatre", "un deux TROIS quatre"),
            1.0
        )
        XCTAssertEqual(
            CorrectionGuardrails.wordSimilarity("un deux trois quatre", "un deux cinq quatre"),
            0.75,
            accuracy: 0.001
        )
    }
}
