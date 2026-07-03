import XCTest
@testable import MintzoCore

/// Post-pass déterministe des remplacements « entendu → voulu » : casse,
/// frontières de mots, multi-occurrences, ordre stable, règles invalides.
final class VocabularyPostPassTests: XCTestCase {

    private func rule(_ heard: String, _ replacement: String) -> VocabularyReplacement {
        VocabularyReplacement(heard: heard, replacement: replacement)
    }

    // MARK: - Cas nominal (exemple du design)

    func testReplacesMultiWordSource() {
        XCTAssertEqual(
            VocabularyPostPass.apply(
                "gaur mine tso probatu dut",
                replacements: [rule("mine tso", "Mintzo")]
            ),
            "gaur Mintzo probatu dut"
        )
    }

    // MARK: - Casse

    func testDetectionIsCaseInsensitive() {
        let rules = [rule("mine tso", "Mintzo")]
        XCTAssertEqual(VocabularyPostPass.apply("Mine Tso da", replacements: rules), "Mintzo da")
        XCTAssertEqual(VocabularyPostPass.apply("MINE TSO da", replacements: rules), "Mintzo da")
    }

    func testTargetCaseIsPreservedVerbatim() {
        // La cible est insérée telle que saisie — jamais adaptée au contexte.
        XCTAssertEqual(
            VocabularyPostPass.apply(
                "on utilise bite ouipe tous les jours",
                replacements: [rule("bite ouipe", "BitWip")]
            ),
            "on utilise BitWip tous les jours"
        )
    }

    // MARK: - Frontières de mots

    func testNoReplacementInsideAWord() {
        // « min » ne doit PAS toucher « Mintzo » ni « hamin ».
        let rules = [rule("min", "douleur")]
        XCTAssertEqual(
            VocabularyPostPass.apply("Mintzo hamin min da", replacements: rules),
            "Mintzo hamin douleur da"
        )
    }

    func testAccentedLettersCountAsWordCharacters() {
        // « été » ne doit pas matcher à l'intérieur de « répété ».
        let rules = [rule("été", "hiver")]
        XCTAssertEqual(
            VocabularyPostPass.apply("il a répété cet été", replacements: rules),
            "il a répété cet hiver"
        )
    }

    func testPunctuationIsAValidBoundary() {
        let rules = [rule("mine tso", "Mintzo")]
        XCTAssertEqual(
            VocabularyPostPass.apply("Kaixo, mine tso!", replacements: rules),
            "Kaixo, Mintzo!"
        )
        XCTAssertEqual(
            VocabularyPostPass.apply("mine tso", replacements: rules),
            "Mintzo",
            "Début et fin de chaîne = frontières valides"
        )
    }

    func testFlexibleWhitespaceInMultiWordSource() {
        // L'ASR peut produire des espaces multiples : tolérés entre les tokens.
        XCTAssertEqual(
            VocabularyPostPass.apply(
                "gaur mine  tso probatu dut",
                replacements: [rule("mine tso", "Mintzo")]
            ),
            "gaur Mintzo probatu dut"
        )
    }

    // MARK: - Multi-occurrences et ordre

    func testReplacesAllOccurrences() {
        XCTAssertEqual(
            VocabularyPostPass.apply(
                "mine tso hemen, mine tso han",
                replacements: [rule("mine tso", "Mintzo")]
            ),
            "Mintzo hemen, Mintzo han"
        )
    }

    func testRulesApplyInStableListOrder() {
        // La sortie de la règle 1 est l'entrée de la règle 2 — ordre de liste.
        let rules = [rule("beta", "gamma"), rule("gamma", "delta")]
        XCTAssertEqual(
            VocabularyPostPass.apply("alpha beta", replacements: rules),
            "alpha delta",
            "beta → gamma (règle 1) puis gamma → delta (règle 2)"
        )
        // Ordre inverse : « gamma » absent du texte au moment de la règle 1.
        XCTAssertEqual(
            VocabularyPostPass.apply("alpha beta", replacements: rules.reversed()),
            "alpha gamma"
        )
    }

    // MARK: - Règles invalides et entrées limites

    func testEmptySidesAreIgnoredNeverErase() {
        XCTAssertEqual(
            VocabularyPostPass.apply("kaixo mundua", replacements: [rule("", "X")]),
            "kaixo mundua"
        )
        XCTAssertEqual(
            VocabularyPostPass.apply("kaixo mundua", replacements: [rule("kaixo", "  ")]),
            "kaixo mundua",
            "Cible vide = règle ignorée, jamais d'effacement de texte dicté"
        )
    }

    func testRegexMetacharactersInSourceAreLiteral() {
        XCTAssertEqual(
            VocabularyPostPass.apply(
                "on note a.b ici",
                replacements: [rule("a.b", "AB")]
            ),
            "on note AB ici"
        )
        XCTAssertEqual(
            VocabularyPostPass.apply("on note axb ici", replacements: [rule("a.b", "AB")]),
            "on note axb ici",
            "Le point de la source est littéral, pas un joker"
        )
    }

    func testDollarInTargetIsLiteral() {
        XCTAssertEqual(
            VocabularyPostPass.apply("prix total", replacements: [rule("prix", "$100")]),
            "$100 total"
        )
    }

    func testEmptyTextAndNoRules() {
        XCTAssertEqual(VocabularyPostPass.apply("", replacements: [rule("a", "b")]), "")
        XCTAssertEqual(VocabularyPostPass.apply("kaixo", replacements: []), "kaixo")
    }
}
