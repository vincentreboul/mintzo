import XCTest
@testable import MintzoCore

/// Corrector stub : renvoie une sortie fixe ou lève.
private struct StubCorrector: Corrector {
    var output: String?

    func correct(_ text: String, language: Language) async throws -> String {
        guard let output else { throw LlamaError.engineUnloaded }
        return output
    }
}

final class CorrectionServiceTests: XCTestCase {
    private let input = "kaixo maite bihar goizean elkartuko gara bulegoan proiektua ixteko ados"

    func testAcceptedCorrectionReturnsCleanedText() async {
        let corrected = "Kaixo, Maite! Bihar goizean elkartuko gara bulegoan, proiektua ixteko. Ados?"
        let service = CorrectionService(corrector: StubCorrector(output: corrected))
        let result = await service.correct(input, language: .basque)
        XCTAssertEqual(result.outcome, .corrected)
        XCTAssertEqual(result.text, corrected)
    }

    func testMetaPrefixedOutputIsCleanedThenAccepted() async {
        let corrected = "Kaixo, Maite! Bihar goizean elkartuko gara bulegoan, proiektua ixteko. Ados?"
        let service = CorrectionService(
            corrector: StubCorrector(output: "Testu zuzendua: \(corrected)")
        )
        let result = await service.correct(input, language: .basque)
        XCTAssertEqual(result.outcome, .corrected)
        XCTAssertEqual(result.text, corrected, "Le préfixe méta doit être nettoyé, pas rejeté")
    }

    func testOverlongOutputFallsBackToRawInput() async {
        let bloated = input + " " + String(repeating: "gauza asko gehitu ditut hemen ", count: 5)
        let service = CorrectionService(corrector: StubCorrector(output: bloated))
        let result = await service.correct(input, language: .basque)
        XCTAssertEqual(result.outcome, .fallbackRaw(reason: .lengthRatio))
        XCTAssertEqual(result.text, input, "En repli, on renvoie le texte BRUT inchangé")
    }

    func testEngineErrorFallsBackToRawInput() async {
        let service = CorrectionService(corrector: StubCorrector(output: nil))
        let result = await service.correct(input, language: .basque)
        XCTAssertEqual(result.outcome, .fallbackRaw(reason: .engineError))
        XCTAssertEqual(result.text, input)
    }

    func testPassthroughReturnsUnchanged() async {
        let service = CorrectionService(corrector: PassthroughCorrector())
        let result = await service.correct(input, language: .basque)
        XCTAssertEqual(result.outcome, .unchanged)
        XCTAssertEqual(result.text, input)
    }

    func testEmptyInputReturnsUnchangedWithoutCallingCorrector() async {
        let service = CorrectionService(corrector: StubCorrector(output: nil)) // lèverait si appelé
        let result = await service.correct("   \n", language: .french)
        XCTAssertEqual(result.outcome, .unchanged)
        XCTAssertEqual(result.text, "")
    }
}
