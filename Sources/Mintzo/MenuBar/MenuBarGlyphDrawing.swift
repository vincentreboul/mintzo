import AppKit

// Dessin vectoriel du mini-lauburu de la barre de menus — reprise en code de
// la « coupe 16 px » de la marque (web/app/static/brand/SPEC.md) : lauburu
// CLASSIQUE PLEIN au compas — chaque bras = demi-cercle extérieur + lobe de
// tête + encoche de queue — les vraies virgules Fraunces étant réservées à
// ≥ 32 px (poussière de pixels en dessous, verdict SPEC).
//
// Chirality de la marque (identique au mark R4) : tête en haut, queue
// plongeant vers le centre en balayant à gauche → les 4 têtes tournent en
// sens horaire. Seules les rotations exactes de 90° de la construction
// existent (interdits SPEC : ni miroir, ni rotation libre).
//
// Fichier AUTONOME (symlinké dans MintzoCoreTests) : dépend d'AppKit seul —
// les couleurs de marque sont passées en paramètres par `MenuBarGlyph`.

enum MenuBarGlyphDrawing {

    /// Canvas 18 × 18 pt — standard menu bar (§5.1 du design language).
    static let canvas: CGFloat = 18

    /// Rayon du lauburu : Ø 12,5 pt ≈ 70 % du canvas — poids optique aligné
    /// sur les icônes système voisines (masse d'encre ≈ 61 pt², équivalente
    /// aux ~66 pt² de l'ancien caret-et-ondes).
    static let lauburuRadius: CGFloat = 6.25

    /// Point 3 pt sous le glyphe (état « traitement », §5.2 adapté).
    static let dotRect = NSRect(x: 7.5, y: 0, width: 3, height: 3)

    /// Badge 3 pt en haut à droite (état « erreur », §5.2) — hors du cercle
    /// du lauburu (distance au centre 8,5 pt > rayon 6,25 pt).
    static let badgeRect = NSRect(x: 15, y: 15, width: 3, height: 3)

    // MARK: - Géométrie

    /// Lauburu classique plein : 4 bras identiques en rotations exactes de 90°
    /// autour de `center` (l'identité des bras est garantie par construction).
    static func lauburuPath(center: NSPoint, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        for quarter in 0..<4 {
            let arm = armPath(radius: radius)
            var transform = AffineTransform.identity
            transform.translate(x: center.x, y: center.y)
            transform.rotate(byDegrees: CGFloat(quarter) * 90)
            arm.transform(using: transform)
            path.append(arm)
        }
        return path
    }

    /// Un bras au compas, pointe en haut, autour de l'origine (le centre du
    /// lauburu). C = origine, T = bout du bras (0, R), M = milieu (0, R/2) :
    /// - demi-cercle EXTÉRIEUR rayon R/2 sur la gauche (C → T par (−R/2, R/2)) ;
    /// - LOBE de tête rayon R/4 sur la droite (T → M par (R/4, 3R/4)) ;
    /// - ENCOCHE de queue rayon R/4 creusée à gauche (M → C par (−R/4, R/4)).
    /// La tête ronde occupe la moitié extérieure ; la queue est le croissant
    /// gauche qui s'effile jusqu'au centre — la virgule classique.
    private static func armPath(radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: .zero)
        path.appendArc(
            withCenter: NSPoint(x: 0, y: radius / 2), radius: radius / 2,
            startAngle: 270, endAngle: 90, clockwise: true
        )
        path.appendArc(
            withCenter: NSPoint(x: 0, y: 3 * radius / 4), radius: radius / 4,
            startAngle: 90, endAngle: 270, clockwise: true
        )
        path.appendArc(
            withCenter: NSPoint(x: 0, y: radius / 4), radius: radius / 4,
            startAngle: 90, endAngle: 270, clockwise: false
        )
        path.close()
        return path
    }

    // MARK: - Rendu

    /// Rend le glyphe (redessiné vectoriellement à chaque échelle d'écran).
    ///
    /// - template `true` : encre noire, seul l'alpha compte (`isTemplate`) —
    ///   s'adapte menu bar claire/sombre/teintée.
    /// - `tint` : couleur du lauburu (enregistrement Gorri Bizi) ; par défaut
    ///   `labelColor`, résolu au dessin selon l'apparence courante.
    /// - `glyphAlpha` : respiration de l'enregistrement (frames pré-calculées).
    /// - `dotAlpha` + `dotColor` : point pulsé sous le glyphe (traitement).
    /// - `badgeColor` : badge erreur en haut à droite.
    static func image(
        template: Bool,
        tint: NSColor? = nil,
        glyphAlpha: CGFloat = 1,
        dotAlpha: CGFloat? = nil,
        dotColor: NSColor = .systemRed,
        badgeColor: NSColor? = nil
    ) -> NSImage {
        let size = NSSize(width: canvas, height: canvas)
        let image = NSImage(size: size, flipped: false) { _ in
            let ink: NSColor = template ? .black : (tint ?? .labelColor)
            ink.withAlphaComponent(glyphAlpha).setFill()
            lauburuPath(
                center: NSPoint(x: canvas / 2, y: canvas / 2),
                radius: lauburuRadius
            ).fill()

            if let dotAlpha {
                dotColor.withAlphaComponent(dotAlpha).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            if let badgeColor {
                badgeColor.setFill()
                NSBezierPath(ovalIn: badgeRect).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
