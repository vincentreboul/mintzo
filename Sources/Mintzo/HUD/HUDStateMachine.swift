import Foundation
import CoreGraphics
import MintzoCore

// Machine d'états du HUD de dictée — logique PURE (Foundation seulement, pas de SwiftUI).
// Source de vérité : docs/design/design-language.md §4.
// Ce fichier est aussi compilé dans MintzoCoreTests (symlink Tests/MintzoCoreTests/HUDStateMachine.swift)
// pour être testé unitairement sans dépendre de la cible app.

// MARK: - États (§4.3)

enum HUDState: Equatable, Sendable {
    /// HUD masqué. L'état « repos / armé » (hotkey pressé, micro s'ouvre) est
    /// `listening` avec un buffer silencieux : 26 points à 3 pt, timer 0:00.
    case idle
    case listening
    case transcribing
    case correcting
    /// Succès. `message` nil = « Itsatsita » (600 ms) ; message custom
    /// (ex. clipboard seul « Arbelean — sakatu ⌘V ») = largeur au contenu, 1,5 s.
    case success(message: String?)
    case error(message: String)

    /// Largeur fixe de la capsule (pt). `nil` = largeur au contenu
    /// (erreur, succès à message custom) ou masqué (idle).
    /// Largeurs §4.3 élargies de ~24 pt : les états actifs portent la croix
    /// d'annulation (18 pt + respiration) en fin de capsule.
    var fixedWidth: CGFloat? {
        switch self {
        case .idle: nil
        case .listening: 236
        case .transcribing, .correcting: 180
        case .success(let message): message == nil ? 112 : nil
        case .error: nil
        }
    }

    /// Largeur maximale (contenu variable plafonné à 320 pt).
    var maxWidth: CGFloat {
        switch self {
        case .error: 320
        case .success(let message) where message != nil: 320
        default: fixedWidth ?? 0
        }
    }

    var isVisible: Bool { self != .idle }

    /// Les états de traitement partagent le trait-shimmer (§4.3 états 2-3).
    var isProcessing: Bool { self == .transcribing || self == .correcting }

    /// Transitions autorisées (§4.3). Tout le reste est un bug d'appelant.
    func canTransition(to next: HUDState) -> Bool {
        switch (self, next) {
        case (.idle, .listening): true
        case (.listening, .transcribing): true
        case (.listening, .idle): true                    // annulation
        case (.listening, .error): true
        case (.transcribing, .correcting): true
        case (.transcribing, .success): true
        case (.transcribing, .error): true
        case (.transcribing, .idle): true                 // annulation
        case (.correcting, .success): true
        case (.correcting, .error): true
        case (.correcting, .idle): true                   // annulation
        case (.success, .idle): true                      // auto : 600 ms (1,5 s si message custom)
        case (.success, .listening): true                 // nouvelle dictée immédiate
        case (.error, .idle): true                        // auto après 4 s ou clic
        case (.error, .listening): true                   // nouvelle dictée immédiate
        case (.error, .error): true                       // mise à jour du message
        default: false
        }
    }
}

// MARK: - Langue (§4.4)

enum HUDLanguage: String, CaseIterable, Sendable {
    case eu, fr, auto

    /// Cycle au clic sur le badge : eu → fr → auto → eu.
    var next: HUDLanguage {
        switch self {
        case .eu: .fr
        case .fr: .auto
        case .auto: .eu
        }
    }

    /// Texte du badge. Auto non résolu : « a→ » (petites caps + flèche).
    var badgeText: String {
        switch self {
        case .eu: "eu"
        case .fr: "fr"
        case .auto: "a\u{2192}"
        }
    }

    /// Langue moteur correspondante — `nil` pour auto (résolue par détection).
    var dictationLanguage: Language? {
        switch self {
        case .eu: .basque
        case .fr: .french
        case .auto: nil
        }
    }

    /// Badge affichant une langue moteur (ex. langue détectée en mode auto).
    init(_ language: Language) {
        self = language == .french ? .fr : .eu
    }
}

// MARK: - Timer m:ss (§4.2)

enum HUDTimerFormatter {
    /// `0:42`, `12:07` — jamais de « s » ni « min » (§3.4).
    static func string(forSeconds seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    struct Display: Equatable, Sendable {
        let text: String
        /// true = décompte des 30 dernières secondes, affiché en MzGorri (§4.2).
        let isCountdown: Bool
    }

    /// Affichage du timer : temps écoulé, ou décompte en Gorri si une limite
    /// technique approche (jamais de plafond silencieux).
    static func display(elapsed: Int, maxDuration: Int?) -> Display {
        if let maxDuration {
            let remaining = maxDuration - elapsed
            if remaining <= 30 {
                return Display(text: string(forSeconds: max(0, remaining)), isCountdown: true)
            }
        }
        return Display(text: string(forSeconds: elapsed), isCountdown: false)
    }
}

// MARK: - Waveform sismographe (§4.2)

enum WaveformMapper {
    static let minHeight: CGFloat = 3
    static let maxHeight: CGFloat = 22
    /// Plancher du mapping log : −50 dBFS → 3 pt, 0 dBFS → 22 pt.
    static let floorDB: Double = -50
    /// En dessous de ce seuil la barre est « silence » (rendue à 28 % d'opacité).
    static let silenceThreshold: CGFloat = 3.25
    /// Facteur d'interpolation linéaire entre deux barres successives (fenêtre 66 ms).
    static let smoothingFactor: Double = 0.55

    /// RMS (0…1) → hauteur de barre, mapping logarithmique 3…22 pt.
    static func height(forRMS rms: Double) -> CGFloat {
        guard rms > 0 else { return minHeight }
        let db = 20 * log10(min(rms, 1))
        let t = max(0, min(1, (db - floorDB) / -floorDB))
        return minHeight + CGFloat(t) * (maxHeight - minHeight)
    }

    /// Lissage : interpolation linéaire depuis la barre précédente vers la cible.
    static func smoothed(previous: CGFloat, target: CGFloat, factor: Double = smoothingFactor) -> CGFloat {
        let f = CGFloat(max(0, min(1, factor)))
        let value = previous + (target - previous) * f
        return max(minHeight, min(maxHeight, value))
    }
}

/// Buffer borné des barres du sismographe. La plus ancienne sort à gauche,
/// la nouvelle entre à droite toutes les 66 ms.
struct WaveformBuffer: Equatable, Sendable {
    let capacity: Int
    private(set) var bars: [CGFloat]

    init(capacity: Int = 26) {
        self.capacity = max(1, capacity)
        self.bars = Array(repeating: WaveformMapper.minHeight, count: self.capacity)
    }

    /// Ajoute une barre depuis un niveau RMS (mapping log + lissage), en évinçant la plus ancienne.
    mutating func append(rms: Double) {
        let target = WaveformMapper.height(forRMS: rms)
        let previous = bars.last ?? WaveformMapper.minHeight
        let value = WaveformMapper.smoothed(previous: previous, target: target)
        bars.removeFirst()
        bars.append(value)
    }

    /// Retour au silence (26 points à 3 pt).
    mutating func reset() {
        bars = Array(repeating: WaveformMapper.minHeight, count: capacity)
    }

    /// Une barre sous le seuil est rendue à 28 % (silence).
    static func isSilent(_ height: CGFloat) -> Bool {
        height <= WaveformMapper.silenceThreshold
    }
}
