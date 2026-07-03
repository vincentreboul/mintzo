import SwiftUI
import AppKit

// Tokens du design language Mintzo — source de vérité : docs/design/design-language.md
// Trois mots-clés d'arbitrage : Tinta (encre), Arnasa (souffle), Harria (pierre).

// MARK: - Couleurs (§2)

enum MzColor {
    static let paper = dynamic("FAF9F7", "171614")
    static let surface = dynamic("FFFFFF", "201E1C")
    static let surfaceHover = dynamic("F3F1ED", "2A2825")
    static let hairline = dynamic("1C1B1A", "F2F0ED", lightAlpha: 0.08, darkAlpha: 0.08)
    static let ink = dynamic("1C1B1A", "F2F0ED")
    static let inkSecondary = dynamic("6B6560", "A39D95")
    static let inkTertiary = dynamic("9B948C", "6E6862")
    /// Accent principal — Gorri Etxea, le rouge oxblood des etxeak labourdines.
    static let gorri = dynamic("9B2D23", "D96A5B")
    /// Accent enregistrement live (waveform, halo).
    static let gorriBizi = dynamic("B5382B", "E87A66")
    static let success = dynamic("3E7A4E", "86C29A")
    // Erreur / avertissement : systemRed / systemOrange (système, ne pas redéfinir).

    private static func dynamic(_ light: String, _ dark: String,
                                lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(mzHex: isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

/// Paliers d'opacité de l'accent (§2.4) — ne jamais inventer d'autres paliers.
enum MzOpacity {
    static let full: Double = 1.0
    static let hoverFill: Double = 0.85
    static let activeBorder: Double = 0.24
    static let tint: Double = 0.12
    static let subtle: Double = 0.08
}

extension NSColor {
    convenience init(mzHex hex: String, alpha: CGFloat = 1) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Typographie (§3) — SF pour la chrome, New York pour le texte dicté uniquement.

enum MzFont {
    // HUD
    static let hudBadge = Font.system(size: 11, weight: .semibold).lowercaseSmallCaps()
    static let hudTimer = Font.system(size: 11, weight: .medium).monospacedDigit()
    static let hudLabel = Font.system(size: 12, weight: .medium)
    // Historique — extrait dicté en serif (le geste éditorial)
    static let historyExcerpt = Font.system(size: 15, design: .serif)
    static let historyMeta = Font.system(size: 11)
    static let historyMetaTag = Font.system(size: 11, weight: .semibold).lowercaseSmallCaps()
    static let sectionHeader = Font.system(size: 11, weight: .semibold).smallCaps()
    // Détail transcription
    static let transcriptBody = Font.system(size: 16, design: .serif)
    // Fenêtre / réglages / onboarding
    static let windowTitle = Font.system(size: 15, weight: .semibold)
    static let settingsBody = Font.system(size: 13)
    static let settingsFootnote = Font.system(size: 11)
    static let onboardingTitle = Font.system(size: 28, weight: .bold)
    static let onboardingBody = Font.system(size: 15)
    static let emptyStateTitle = Font.system(size: 22, design: .serif)

    // Interlignages (lineSpacing SwiftUI = espace ADDITIONNEL au-delà de la ligne naturelle)
    static let historyExcerptLineSpacing: CGFloat = 4   // ≈ 15/22
    static let transcriptBodyLineSpacing: CGFloat = 6   // ≈ 16/26
    static let onboardingBodyLineSpacing: CGFloat = 4   // ≈ 15/22
    // Tracking (à appliquer via .tracking() côté vue)
    static let sectionHeaderTracking: CGFloat = 1.0
    static let hudBadgeTracking: CGFloat = 0.6
}

// MARK: - Motion (§7) — Arnasa : l'app respire, elle ne vibre pas.

enum MzMotion {
    /// Apparition HUD, overlay drop, hover reveals — 180 ms
    static let enter = Animation.spring(response: 0.32, dampingFraction: 0.80)
    /// Changements d'état HUD (largeur + contenu) — 240 ms
    static let morph = Animation.spring(response: 0.32, dampingFraction: 0.80)
    /// Disparition HUD, dismiss overlays — 220 ms
    static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.22)
    /// Crossfades de labels, hovers, checkmark copie — 160 ms
    static let micro = Animation.timingCurve(0, 0, 0.2, 1, duration: 0.16)
    /// Halo d'écoute : opacité 12 % → 18 % → 12 %, boucle
    static let breath = Animation.easeInOut(duration: 3.2).repeatForever(autoreverses: true)
    /// Insertion d'une cellule dans l'historique
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.85)

    static let shimmerDuration: TimeInterval = 1.1
    /// Une nouvelle barre de waveform entre toutes les 66 ms (sismographe)
    static let waveformTick: TimeInterval = 0.066
    static let successHoldDuration: TimeInterval = 0.6
    static let errorHoldDuration: TimeInterval = 4.0
}

// MARK: - Métriques HUD (§4)

enum MzHUD {
    static let height: CGFloat = 36
    static let cornerRadius: CGFloat = 18
    static let paddingH: CGFloat = 14
    static let itemSpacing: CGFloat = 10
    static let bottomOffset: CGFloat = 24
    static let widthListening: CGFloat = 208
    static let widthProcessing: CGFloat = 156
    static let widthSuccess: CGFloat = 112
    static let widthErrorMax: CGFloat = 320
    // Waveform sismographe
    static let waveformBarCount = 26
    static let waveformBarWidth: CGFloat = 2
    static let waveformBarGap: CGFloat = 2
    static let waveformBarMinHeight: CGFloat = 3
    static let waveformBarMaxHeight: CGFloat = 22
}
