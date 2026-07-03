import XCTest
@testable import MintzoCore

/// Injection des graphies du dictionnaire dans le prompt système de correction.
final class CorrectionPromptVocabularyTests: XCTestCase {

    func testBasquePromptGainsProtectedWordsSection() {
        let prompt = CorrectionPrompt.system(for: .basque, protectedWords: ["Bitwip", "Maite"])
        XCTAssertTrue(prompt.contains("Errespetatu ZEHAZKI grafia hauek"),
                      "Section euskara attendue")
        XCTAssertTrue(prompt.contains("Bitwip, Maite."))
        XCTAssertTrue(prompt.hasPrefix(CorrectionPrompt.system(for: .basque)),
                      "Le prompt de base doit rester intact devant la section")
    }

    func testFrenchPromptGainsProtectedWordsSection() {
        let prompt = CorrectionPrompt.system(for: .french, protectedWords: ["Bitwip", "Donostia"])
        XCTAssertTrue(prompt.contains("Respecte exactement ces graphies"),
                      "Section française attendue")
        XCTAssertTrue(prompt.contains("Bitwip, Donostia."))
        XCTAssertTrue(prompt.hasPrefix(CorrectionPrompt.system(for: .french)))
    }

    func testEmptyWordsLeavePromptStrictlyUnchanged() {
        for language in Language.allCases {
            XCTAssertEqual(
                CorrectionPrompt.system(for: language, protectedWords: []),
                CorrectionPrompt.system(for: language),
                "Liste vide = prompt historique, octet pour octet"
            )
            XCTAssertEqual(
                CorrectionPrompt.system(for: language, protectedWords: ["", "  "]),
                CorrectionPrompt.system(for: language),
                "Mots blancs ignorés = pas de section vide"
            )
        }
    }

    func testProtectedWordsAreTruncatedByWholeWords() {
        // Même politique de troncature prudente que l'amorce whisper : la
        // section ne doit jamais gonfler sans borne le contexte du LLM.
        let many = (0..<500).map { "Hitzalde\($0)" }
        let prompt = CorrectionPrompt.system(for: .basque, protectedWords: many)
        let base = CorrectionPrompt.system(for: .basque)
        XCTAssertLessThanOrEqual(
            prompt.count - base.count,
            VocabularyPrompt.maxLength + 64, // section + libellé
            "La liste injectée doit être bornée"
        )
        XCTAssertFalse(prompt.contains("Hitzalde499"), "Queue de liste abandonnée")
    }
}
