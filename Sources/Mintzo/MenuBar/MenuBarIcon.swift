import AppKit
import SwiftUI

// Icône menu bar — le mini-lauburu de la marque (coupe classique pleine 16 px
// de brand/SPEC.md, redessinée 18 pt dans `MenuBarGlyphDrawing`), template au
// repos. Aucun micro, aucune bulle, aucun emoji.
//
// États §5.2 adaptés au lauburu (le caret-et-ondes n'existe plus) :
// - repos : glyphe template monochrome ;
// - enregistrement : lauburu teinté `MzGorriBizi`, respiration d'opacité
//   Arnasa (cycle 1,8 s, 6 frames) — la rotation animée est écartée : le sens
//   de rotation EST la marque, seules les rotations 90° existent (interdits SPEC) ;
// - traitement : point 3 pt `MzGorri` sous le glyphe, pulse 1,6 s ;
// - erreur : badge point 3 pt `systemOrange` en haut à droite ;
// - bascule de langue hors session : texte « eu »/« fr » 1 s (vue ci-dessous).

/// État de l'icône menu bar (§5.2), dérivé de la machine d'états du HUD.
enum MenuBarState: Equatable, Sendable {
    case idle
    case recording
    case processing
    case error
}

enum MenuBarGlyph {
    static let canvas: CGFloat = MenuBarGlyphDrawing.canvas

    /// Cadence de la respiration d'enregistrement : 6 frames × 0,3 s = 1,8 s (Arnasa).
    static let recordingFrameInterval: TimeInterval = 0.3
    static let recordingFrameCount = 6
    static let processingPulseDuration: TimeInterval = 1.6
    static let languageFlashDuration: TimeInterval = 1.0

    // Couleurs : MzNSColor.gorri / .gorriBizi (DesignSystem) — plus de miroir local.

    // MARK: Images (cachées — jamais recalculées par frame)

    /// Repos : lauburu template monochrome.
    static let idle: NSImage = MenuBarGlyphDrawing.image(template: true)

    /// Enregistrement : lauburu GorriBizi, opacité en respiration sinusoïdale
    /// douce (1,0 → 0,62 → 1,0 sur 1,8 s) — le moment de marque (§2.2).
    static let recordingFrames: [NSImage] = (0..<recordingFrameCount).map { index in
        let phase = Double(index) / Double(recordingFrameCount)
        let alpha = 0.62 + 0.38 * (0.5 + 0.5 * sin(phase * 2 * .pi + .pi / 2))
        return MenuBarGlyphDrawing.image(
            template: false,
            tint: MzNSColor.gorriBizi,
            glyphAlpha: alpha
        )
    }

    /// Traitement : lauburu + point 3 pt Gorri sous le glyphe, pulse 1,6 s (8 frames cachées).
    static let processingFrames: [NSImage] = (0..<8).map { index in
        let phase = Double(index) / 8
        let alpha = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase * 2 * .pi))
        return MenuBarGlyphDrawing.image(
            template: false,
            dotAlpha: alpha,
            dotColor: MzNSColor.gorri
        )
    }

    /// Erreur (modèle manquant, permission) : badge point 3 pt orange en haut à droite.
    static let error: NSImage = MenuBarGlyphDrawing.image(
        template: false,
        badgeColor: .systemOrange
    )
}

// MARK: - Vue label du MenuBarExtra

/// Icône vivante : repos template, enregistrement en lauburu GorriBizi
/// respirant (cycle 1,8 s), traitement en point pulsé (1,6 s), erreur badgée
/// orange. Bascule de langue hors session : le glyphe laisse place au texte 1 s (§5.2).
///
/// Vue PASSIVE : la cadence d'animation vient d'AppModel (`frame` incrémenté par une
/// Task). JAMAIS de TimelineView ici — un schedule ré-ancré dans un label de
/// MenuBarExtra relance updateButton en boucle et sature le main thread (observé).
struct MenuBarIconView: View {
    let state: MenuBarState
    let frame: Int
    let languageFlash: HUDLanguage?

    var body: some View {
        if let languageFlash {
            Text(languageFlash.badgeText)
                .font(Font.system(size: 11, weight: .semibold).lowercaseSmallCaps())
                .tracking(MzFont.hudBadgeTracking)
        } else {
            switch state {
            case .idle:
                Image(nsImage: MenuBarGlyph.idle)
            case .recording:
                Image(nsImage: MenuBarGlyph.recordingFrames[frame % MenuBarGlyph.recordingFrames.count])
            case .processing:
                Image(nsImage: MenuBarGlyph.processingFrames[frame % MenuBarGlyph.processingFrames.count])
            case .error:
                Image(nsImage: MenuBarGlyph.error)
            }
        }
    }
}
