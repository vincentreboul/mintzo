import AppKit
import SwiftUI

// Icône menu bar — concept « le point d'insertion qui écoute » (§5.1) :
// un caret flanqué de 4 barres d'onde. Dessinée en code, canvas 18 × 18 pt,
// template au repos. Aucun micro, aucune bulle, aucun emoji.

/// État de l'icône menu bar (§5.2), dérivé de la machine d'états du HUD.
enum MenuBarState: Equatable, Sendable {
    case idle
    case recording
    case processing
    case error
}

enum MenuBarGlyph {
    static let canvas: CGFloat = 18
    /// Hauteurs (extérieures, intérieures) au repos (§5.1).
    static let restingHeights: (outer: CGFloat, inner: CGFloat) = (4, 7)
    /// 3 jeux de hauteurs pré-calculés pour l'enregistrement, cycle 900 ms (§5.2).
    static let recordingHeights: [(outer: CGFloat, inner: CGFloat)] = [(4, 7), (6, 10), (3, 5)]
    static let recordingFrameInterval: TimeInterval = 0.3
    static let processingPulseDuration: TimeInterval = 1.6
    static let languageFlashDuration: TimeInterval = 1.0

    // MARK: Couleurs NSColor (miroir de MzColor — à remonter au DesignSystem si NSColor requis ailleurs)

    static let gorriNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(mzHex: "D96A5B") : NSColor(mzHex: "9B2D23")
    }
    static let gorriBiziNSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(mzHex: "E87A66") : NSColor(mzHex: "B5382B")
    }

    // MARK: Images (cachées — jamais recalculées par frame)

    /// Repos : glyphe template monochrome.
    static let idle: NSImage = draw(template: true)

    /// Enregistrement : barres teintées GorriBizi animées, caret en labelColor.
    static let recordingFrames: [NSImage] = recordingHeights.map { heights in
        draw(template: false, barHeights: heights, barColor: gorriBiziNSColor)
    }

    /// Traitement : glyphe + point 3 pt Gorri sous le caret, pulse 1,6 s (8 frames cachées).
    static let processingFrames: [NSImage] = (0..<8).map { index in
        let phase = Double(index) / 8
        let alpha = 0.35 + 0.65 * (0.5 + 0.5 * sin(phase * 2 * .pi))
        return draw(template: false, dotAlpha: alpha)
    }

    /// Erreur (modèle manquant, permission) : badge point 3 pt orange en haut à droite.
    static let error: NSImage = draw(template: false, withErrorBadge: true)

    // MARK: Dessin vectoriel (§5.1)

    /// Caret capsule 2 × 12 centré (x 9, y 3→15) ; barres capsules 2 pt centrées y 9 :
    /// intérieures x 4.5 / 13.5, extérieures x 1.5 / 16.5.
    private static func draw(
        template: Bool,
        barHeights: (outer: CGFloat, inner: CGFloat) = restingHeights,
        barColor: NSColor? = nil,
        dotAlpha: Double? = nil,
        withErrorBadge: Bool = false
    ) -> NSImage {
        let size = NSSize(width: canvas, height: canvas)
        let image = NSImage(size: size, flipped: false) { _ in
            // Template : alpha seul compte. Sinon labelColor s'adapte à la menu bar au dessin.
            let inkColor: NSColor = template ? .black : .labelColor
            let waveColor = barColor ?? inkColor

            func capsule(cx: CGFloat, cy: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
                color.setFill()
                let rect = NSRect(x: cx - width / 2, y: cy - height / 2, width: width, height: height)
                NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
            }

            capsule(cx: 9, cy: 9, width: 2, height: 12, color: inkColor)                    // caret
            capsule(cx: 4.5, cy: 9, width: 2, height: barHeights.inner, color: waveColor)   // intérieures
            capsule(cx: 13.5, cy: 9, width: 2, height: barHeights.inner, color: waveColor)
            capsule(cx: 1.5, cy: 9, width: 2, height: barHeights.outer, color: waveColor)   // extérieures
            capsule(cx: 16.5, cy: 9, width: 2, height: barHeights.outer, color: waveColor)

            if let dotAlpha {
                gorriNSColor.withAlphaComponent(dotAlpha).setFill()
                NSBezierPath(ovalIn: NSRect(x: 7.5, y: 0, width: 3, height: 3)).fill()      // point sous le caret
            }
            if withErrorBadge {
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: NSRect(x: 15, y: 15, width: 3, height: 3)).fill()      // badge haut-droite
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}

// MARK: - Vue label du MenuBarExtra

/// Icône vivante : repos template, enregistrement en barres GorriBizi (cycle 900 ms),
/// traitement en point pulsé (1,6 s), erreur badgée orange.
/// Bascule de langue hors session : le glyphe laisse place au texte 1 s (§5.2).
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
