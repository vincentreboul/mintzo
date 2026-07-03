import AppKit
import XCTest
@testable import MintzoCore

/// Tests de l'InsertionService sur un pasteboard nommé privé — JAMAIS le
/// `.general`. La simulation CGEvent (permission Accessibility) n'est pas
/// testée unitairement : elle est isolée derrière `KeystrokeSimulating`,
/// mockée ici, exercée à l'intégration.
@MainActor
final class SystemInsertionTests: XCTestCase {

    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        // Un pasteboard unique par test : aucune pollution croisée, aucun
        // risque pour le clipboard de la machine.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("mintzo-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    // MARK: - Doubles

    private final class KeystrokeSpy: KeystrokeSimulating {
        struct SimulatedFailure: Error {}
        private(set) var pasteCount = 0
        var shouldFail = false
        var onPaste: (@MainActor () -> Void)?

        func simulatePaste() throws {
            if shouldFail { throw SimulatedFailure() }
            pasteCount += 1
            onPaste?()
        }
    }

    private func makeService(
        spy: KeystrokeSpy = KeystrokeSpy(),
        secureInput: Bool = false,
        accessibilityTrusted: Bool = true
    ) -> (InsertionService, KeystrokeSpy) {
        let service = InsertionService(
            pasteboard: pasteboard,
            keystrokes: spy,
            environment: InsertionEnvironment(
                isSecureInputActive: { secureInput },
                isAccessibilityTrusted: { accessibilityTrusted }
            ),
            timing: .immediate
        )
        return (service, spy)
    }

    private let rtfSample = Data("{\\rtf1\\ansi ancien contenu {\\b gras}}".utf8)

    /// Pré-remplit le pasteboard avec un item multi-types (string + rtf).
    private func seedPasteboardWithStringAndRTF() {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("ancien contenu", forType: .string)
        item.setData(rtfSample, forType: .rtf)
        pasteboard.writeObjects([item])
    }

    // MARK: - Cycle save / write / restore

    func testHappyPathPastesThenRestoresStringAndRTF() async throws {
        seedPasteboardWithStringAndRTF()
        let (service, spy) = makeService()

        // Au moment du Cmd+V simulé, le pasteboard doit contenir la transcription.
        spy.onPaste = { [pasteboard] in
            XCTAssertEqual(pasteboard?.string(forType: .string), "kaixo mundua")
        }

        let result = await service.insert("kaixo mundua")

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(spy.pasteCount, 1)
        // Restauration fidèle : les deux types sur le même item.
        XCTAssertEqual(pasteboard.string(forType: .string), "ancien contenu")
        XCTAssertEqual(pasteboard.data(forType: .rtf), rtfSample)
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 1)
        // AppKit ajoute des types dérivés (ex. utf16-external-plain-text) :
        // on exige la présence des types d'origine, pas l'égalité stricte.
        XCTAssertTrue(
            Set(pasteboard.pasteboardItems?.first?.types ?? []).isSuperset(of: [.string, .rtf])
        )
    }

    func testEmptyTextIsCleanNoOp() async {
        seedPasteboardWithStringAndRTF()
        let countBefore = pasteboard.changeCount
        let (service, spy) = makeService()

        let result = await service.insert("")

        XCTAssertEqual(result, .nothingToInsert)
        XCTAssertEqual(spy.pasteCount, 0, "aucune frappe pour un texte vide")
        XCTAssertEqual(pasteboard.changeCount, countBefore, "le pasteboard ne doit pas être touché")
        XCTAssertEqual(pasteboard.string(forType: .string), "ancien contenu")
    }

    func testEmptyOriginalPasteboardRestoresToEmpty() async {
        pasteboard.clearContents()
        let (service, spy) = makeService()

        let result = await service.insert("testua")

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(spy.pasteCount, 1)
        XCTAssertNil(pasteboard.string(forType: .string),
                     "un pasteboard vide avant doit rester vide après restauration")
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty ?? true)
    }

    // MARK: - Garde-fous (jamais de frappe simulée)

    func testSecureInputActiveGoesClipboardOnlyWithoutKeystroke() async {
        seedPasteboardWithStringAndRTF()
        let (service, spy) = makeService(secureInput: true)

        let result = await service.insert("pasahitza ez")

        XCTAssertEqual(result, .clipboardOnly(reason: .secureInputActive))
        XCTAssertEqual(spy.pasteCount, 0, "JAMAIS de CGEvent quand un champ sécurisé est actif")
        // Le texte doit RESTER disponible pour un Cmd+V manuel.
        XCTAssertEqual(pasteboard.string(forType: .string), "pasahitza ez")
        XCTAssertNil(pasteboard.data(forType: .rtf), "pas de restauration en mode clipboard-seul")
    }

    func testAccessibilityMissingGoesClipboardOnlyWithoutKeystroke() async {
        let (service, spy) = makeService(accessibilityTrusted: false)

        let result = await service.insert("baimenik gabe")

        XCTAssertEqual(result, .clipboardOnly(reason: .accessibilityNotGranted))
        XCTAssertEqual(spy.pasteCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "baimenik gabe")
    }

    func testKeystrokeFailureLeavesTextOnClipboard() async {
        seedPasteboardWithStringAndRTF()
        let spy = KeystrokeSpy()
        spy.shouldFail = true
        let (service, _) = makeService(spy: spy)

        let result = await service.insert("huts egin du")

        XCTAssertEqual(result, .clipboardOnly(reason: .keystrokeSimulationFailed))
        XCTAssertEqual(pasteboard.string(forType: .string), "huts egin du",
                       "après échec de frappe, le texte reste collable manuellement")
    }

    // MARK: - Race clipboard manager

    func testExternalWriteDuringPasteSkipsRestore() async {
        seedPasteboardWithStringAndRTF()
        let spy = KeystrokeSpy()
        // Un clipboard manager (ou l'utilisateur) écrit pendant le paste :
        // la restauration ne doit PAS écraser ce nouveau contenu.
        spy.onPaste = { [pasteboard] in
            pasteboard?.clearContents()
            pasteboard?.setString("intrus", forType: .string)
        }
        let (service, _) = makeService(spy: spy)

        let result = await service.insert("transkripzioa")

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(pasteboard.string(forType: .string), "intrus",
                       "le contenu écrit par un tiers pendant le paste doit survivre")
    }

    // MARK: - Simulateur réel (sans post d'événement)

    func testCGEventSimulatorBuildsWithoutError() {
        // On vérifie seulement la construction (aucun post ici : cela
        // collerait réellement dans l'app active et exige Accessibility).
        _ = CGEventKeystrokeSimulator()
    }
}
