import XCTest

// Tests de la machine d'états du HUD (docs/design/design-language.md §4).
// HUDStateMachine.swift est compilé directement dans ce bundle de test
// (symlink Tests/MintzoCoreTests/HUDStateMachine.swift) — pas d'import de la cible app.

final class HUDStateMachineTests: XCTestCase {

    // MARK: Transitions (§4.3)

    func testNominalDictationFlow() {
        XCTAssertTrue(HUDState.idle.canTransition(to: .listening))
        XCTAssertTrue(HUDState.listening.canTransition(to: .transcribing))
        XCTAssertTrue(HUDState.transcribing.canTransition(to: .correcting))
        XCTAssertTrue(HUDState.correcting.canTransition(to: .success(message: nil)))
        XCTAssertTrue(HUDState.success(message: nil).canTransition(to: .idle))
    }

    func testFlowWithoutCorrection() {
        XCTAssertTrue(HUDState.transcribing.canTransition(to: .success(message: nil)))
    }

    func testCancellationsReturnToIdle() {
        XCTAssertTrue(HUDState.listening.canTransition(to: .idle))
        XCTAssertTrue(HUDState.transcribing.canTransition(to: .idle))
        XCTAssertTrue(HUDState.correcting.canTransition(to: .idle))
    }

    func testErrorsFromActiveStates() {
        XCTAssertTrue(HUDState.listening.canTransition(to: .error(message: "e")))
        XCTAssertTrue(HUDState.transcribing.canTransition(to: .error(message: "e")))
        XCTAssertTrue(HUDState.correcting.canTransition(to: .error(message: "e")))
        XCTAssertTrue(HUDState.error(message: "a").canTransition(to: .error(message: "b")),
                      "Mise à jour du message d'erreur autorisée")
        XCTAssertTrue(HUDState.error(message: "e").canTransition(to: .idle))
    }

    func testImmediateRedictationAfterTerminalStates() {
        XCTAssertTrue(HUDState.success(message: nil).canTransition(to: .listening))
        XCTAssertTrue(HUDState.error(message: "e").canTransition(to: .listening))
    }

    func testForbiddenTransitions() {
        XCTAssertFalse(HUDState.idle.canTransition(to: .transcribing))
        XCTAssertFalse(HUDState.idle.canTransition(to: .success(message: nil)))
        XCTAssertFalse(HUDState.idle.canTransition(to: .error(message: "e")))
        XCTAssertFalse(HUDState.listening.canTransition(to: .correcting),
                       "La correction ne peut suivre que la transcription")
        XCTAssertFalse(HUDState.listening.canTransition(to: .success(message: nil)))
        XCTAssertFalse(HUDState.correcting.canTransition(to: .transcribing),
                       "Pas de retour en arrière dans le pipeline")
        XCTAssertFalse(HUDState.success(message: nil).canTransition(to: .error(message: "e")))
        XCTAssertFalse(HUDState.success(message: nil).canTransition(to: .transcribing))
        XCTAssertFalse(HUDState.listening.canTransition(to: .listening))
    }

    // MARK: Largeurs exactes (§4.3)

    func testCapsuleWidthsPerState() {
        XCTAssertNil(HUDState.idle.fixedWidth)
        XCTAssertEqual(HUDState.listening.fixedWidth, 208)
        XCTAssertEqual(HUDState.transcribing.fixedWidth, 156)
        XCTAssertEqual(HUDState.correcting.fixedWidth, 156)
        XCTAssertEqual(HUDState.success(message: nil).fixedWidth, 112)
        XCTAssertNil(HUDState.error(message: "e").fixedWidth, "Erreur : largeur au contenu")
        XCTAssertEqual(HUDState.error(message: "e").maxWidth, 320)
    }

    // MARK: Succès à message custom (clipboard seul, §4.3 état 4)

    func testSuccessWithCustomMessage() {
        let clipboard = HUDState.success(message: "Arbelean — sakatu ⌘V")
        XCTAssertNil(clipboard.fixedWidth, "Message custom : largeur au contenu")
        XCTAssertEqual(clipboard.maxWidth, 320, "Plafond identique à l'erreur")
        XCTAssertEqual(HUDState.success(message: nil).maxWidth, 112,
                       "« Itsatsita » : largeur fixe inchangée")
        XCTAssertTrue(clipboard.isVisible)
        XCTAssertFalse(clipboard.isProcessing)
        // Mêmes transitions que le succès standard.
        XCTAssertTrue(HUDState.transcribing.canTransition(to: clipboard))
        XCTAssertTrue(HUDState.correcting.canTransition(to: clipboard))
        XCTAssertTrue(clipboard.canTransition(to: .idle))
        XCTAssertTrue(clipboard.canTransition(to: .listening))
        XCTAssertFalse(HUDState.idle.canTransition(to: clipboard))
        XCTAssertFalse(HUDState.listening.canTransition(to: clipboard))
    }

    func testVisibilityAndProcessingFlags() {
        XCTAssertFalse(HUDState.idle.isVisible)
        XCTAssertTrue(HUDState.listening.isVisible)
        XCTAssertTrue(HUDState.transcribing.isProcessing)
        XCTAssertTrue(HUDState.correcting.isProcessing)
        XCTAssertFalse(HUDState.listening.isProcessing)
        XCTAssertFalse(HUDState.success(message: nil).isProcessing)
    }

    // MARK: Timer m:ss (§4.2, §3.4)

    func testTimerFormatting() {
        XCTAssertEqual(HUDTimerFormatter.string(forSeconds: 0), "0:00")
        XCTAssertEqual(HUDTimerFormatter.string(forSeconds: 7), "0:07")
        XCTAssertEqual(HUDTimerFormatter.string(forSeconds: 42), "0:42")
        XCTAssertEqual(HUDTimerFormatter.string(forSeconds: 61), "1:01")
        XCTAssertEqual(HUDTimerFormatter.string(forSeconds: 600), "10:00")
        XCTAssertEqual(HUDTimerFormatter.string(forSeconds: 727), "12:07")
        XCTAssertEqual(HUDTimerFormatter.string(forSeconds: -3), "0:00", "Jamais de temps négatif")
    }

    func testTimerCountdownOnLastThirtySeconds() {
        // Sans limite : jamais de décompte.
        let unlimited = HUDTimerFormatter.display(elapsed: 3600, maxDuration: nil)
        XCTAssertEqual(unlimited.text, "60:00")
        XCTAssertFalse(unlimited.isCountdown)
        // Limite loin : temps écoulé normal.
        let far = HUDTimerFormatter.display(elapsed: 80, maxDuration: 120)
        XCTAssertEqual(far.text, "1:20")
        XCTAssertFalse(far.isCountdown)
        // 30 dernières secondes : décompte en Gorri.
        let near = HUDTimerFormatter.display(elapsed: 95, maxDuration: 120)
        XCTAssertEqual(near.text, "0:25")
        XCTAssertTrue(near.isCountdown)
        // Limite atteinte : plancher 0:00, jamais négatif.
        let over = HUDTimerFormatter.display(elapsed: 130, maxDuration: 120)
        XCTAssertEqual(over.text, "0:00")
        XCTAssertTrue(over.isCountdown)
    }

    // MARK: Langue (§4.4)

    func testLanguageCycle() {
        XCTAssertEqual(HUDLanguage.eu.next, .fr)
        XCTAssertEqual(HUDLanguage.fr.next, .auto)
        XCTAssertEqual(HUDLanguage.auto.next, .eu)
        // Le cycle complet revient au départ.
        XCTAssertEqual(HUDLanguage.eu.next.next.next, .eu)
    }

    func testLanguageBadgeTexts() {
        XCTAssertEqual(HUDLanguage.eu.badgeText, "eu")
        XCTAssertEqual(HUDLanguage.fr.badgeText, "fr")
        XCTAssertEqual(HUDLanguage.auto.badgeText, "a\u{2192}", "Auto non résolu : « a→ »")
    }

    func testLanguageBridgesToDictationLanguage() {
        // Pont badge → langue moteur : auto n'a PAS de langue fixe (détection).
        XCTAssertEqual(HUDLanguage.eu.dictationLanguage, .basque)
        XCTAssertEqual(HUDLanguage.fr.dictationLanguage, .french)
        XCTAssertNil(HUDLanguage.auto.dictationLanguage)
        // Pont langue moteur → badge (langue détectée affichée en Gorri).
        XCTAssertEqual(HUDLanguage(.basque), .eu)
        XCTAssertEqual(HUDLanguage(.french), .fr)
    }

    // MARK: Mapping RMS → hauteur log 3…22 pt (§4.2)

    func testWaveformMappingBounds() {
        XCTAssertEqual(WaveformMapper.height(forRMS: 0), 3)
        XCTAssertEqual(WaveformMapper.height(forRMS: 1), 22, accuracy: 0.001)
        XCTAssertEqual(WaveformMapper.height(forRMS: 2), 22, accuracy: 0.001, "RMS > 1 plafonné")
        XCTAssertEqual(WaveformMapper.height(forRMS: -1), 3, "RMS négatif → silence")
        // −50 dB et en dessous → plancher 3 pt.
        XCTAssertEqual(WaveformMapper.height(forRMS: 0.00316), 3, accuracy: 0.01)
        XCTAssertEqual(WaveformMapper.height(forRMS: 0.0001), 3)
    }

    func testWaveformMappingIsLogarithmicAndMonotonic() {
        // −30 dB (rms 0.0316) → t = 0.4 → 3 + 0.4 × 19 = 10.6 pt.
        XCTAssertEqual(WaveformMapper.height(forRMS: 0.0316), 10.6, accuracy: 0.05)
        // −10 dB (rms 0.316) → t = 0.8 → 18.2 pt : le mapping log favorise la voix.
        XCTAssertEqual(WaveformMapper.height(forRMS: 0.316), 18.2, accuracy: 0.05)
        var previous: CGFloat = 0
        for rms in stride(from: 0.001, through: 1.0, by: 0.013) {
            let h = WaveformMapper.height(forRMS: rms)
            XCTAssertGreaterThanOrEqual(h, previous, "Le mapping doit être monotone")
            XCTAssertGreaterThanOrEqual(h, 3)
            XCTAssertLessThanOrEqual(h, 22)
            previous = h
        }
    }

    func testWaveformSmoothing() {
        // Le lissage interpole : depuis le silence vers un pic, la barre n'atteint pas la cible d'un coup.
        let smoothed = WaveformMapper.smoothed(previous: 3, target: 22)
        XCTAssertGreaterThan(smoothed, 3)
        XCTAssertLessThan(smoothed, 22)
        // Convergence en quelques ticks.
        var value: CGFloat = 3
        for _ in 0..<12 { value = WaveformMapper.smoothed(previous: value, target: 22) }
        XCTAssertEqual(value, 22, accuracy: 0.2)
        // Bornes respectées quel que soit le facteur.
        XCTAssertEqual(WaveformMapper.smoothed(previous: 3, target: 100, factor: 5), 22)
        XCTAssertEqual(WaveformMapper.smoothed(previous: 22, target: -50, factor: 5), 3)
    }

    // MARK: Buffer waveform borné (§4.2)

    func testWaveformBufferStartsSilentAtCapacity() {
        let buffer = WaveformBuffer(capacity: 26)
        XCTAssertEqual(buffer.bars.count, 26)
        XCTAssertTrue(buffer.bars.allSatisfy { $0 == 3 }, "Armé : 26 points à 3 pt")
    }

    func testWaveformBufferStaysBounded() {
        var buffer = WaveformBuffer(capacity: 26)
        for i in 0..<500 {
            buffer.append(rms: Double(i % 10) / 10)
            XCTAssertEqual(buffer.bars.count, 26, "Le buffer ne doit jamais déborder")
            XCTAssertTrue(buffer.bars.allSatisfy { $0 >= 3 && $0 <= 22 },
                          "Toute barre reste dans 3…22 pt")
        }
    }

    func testWaveformBufferScrollsOldestOut() {
        var buffer = WaveformBuffer(capacity: 4)
        buffer.append(rms: 1.0)   // pic
        let peak = buffer.bars.last!
        XCTAssertGreaterThan(peak, 3)
        buffer.append(rms: 0)
        buffer.append(rms: 0)
        buffer.append(rms: 0)
        // Le pic a glissé jusqu'à la position 0 (plus ancienne)…
        XCTAssertEqual(buffer.bars.first!, peak)
        buffer.append(rms: 0)
        // …puis est évincé.
        XCTAssertFalse(buffer.bars.contains(peak))
    }

    func testWaveformBufferReset() {
        var buffer = WaveformBuffer(capacity: 26)
        for _ in 0..<30 { buffer.append(rms: 0.9) }
        buffer.reset()
        XCTAssertEqual(buffer.bars, Array(repeating: 3, count: 26))
    }

    func testSilenceThreshold() {
        XCTAssertTrue(WaveformBuffer.isSilent(3))
        XCTAssertTrue(WaveformBuffer.isSilent(3.2))
        XCTAssertFalse(WaveformBuffer.isSilent(4))
        XCTAssertFalse(WaveformBuffer.isSilent(22))
    }
}
