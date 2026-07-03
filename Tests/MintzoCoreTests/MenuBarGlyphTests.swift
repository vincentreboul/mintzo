import AppKit
import XCTest

/// Tests du dessin du mini-lauburu (`MenuBarGlyphDrawing`, symlinké dans la
/// target — même pattern que HUDStateMachine) : géométrie, symétrie de
/// rotation d'ordre 4, chirality de la marque, états dot/badge.
final class MenuBarGlyphTests: XCTestCase {

    /// 18 pt rendus à 4× (72 px) — même échelle que le harnais de captures.
    private static let scale: CGFloat = 4
    private static let side = Int(MenuBarGlyphDrawing.canvas * scale)

    // MARK: - Helpers raster

    private func rasterize(_ image: NSImage) -> NSBitmapImageRep {
        let side = Self.side
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            fatalError("bitmap rep indisponible")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Alpha du pixel en coordonnées POINTS y-vers-le-haut (comme le dessin).
    private func alpha(_ rep: NSBitmapImageRep, ptX: CGFloat, ptY: CGFloat) -> CGFloat {
        let col = min(Self.side - 1, max(0, Int(ptX * Self.scale)))
        let row = min(Self.side - 1, max(0, Self.side - 1 - Int(ptY * Self.scale)))
        return rep.colorAt(x: col, y: row)?.alphaComponent ?? 0
    }

    private var center: CGFloat { MenuBarGlyphDrawing.canvas / 2 }
    private var radius: CGFloat { MenuBarGlyphDrawing.lauburuRadius }

    // MARK: - Contrats d'image

    func testImagesAre18ptCanvas() {
        let image = MenuBarGlyphDrawing.image(template: true)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }

    func testTemplateFlagFollowsParameter() {
        XCTAssertTrue(MenuBarGlyphDrawing.image(template: true).isTemplate,
                      "repos = template : s'adapte à la menu bar claire/sombre/teintée")
        XCTAssertFalse(MenuBarGlyphDrawing.image(template: false, tint: .red).isTemplate,
                       "états teintés : jamais template (la couleur doit survivre)")
    }

    // MARK: - Géométrie

    func testLauburuInscribedInItsCircle() {
        let path = MenuBarGlyphDrawing.lauburuPath(
            center: NSPoint(x: center, y: center), radius: radius
        )
        let expected = NSRect(
            x: center - radius, y: center - radius,
            width: 2 * radius, height: 2 * radius
        )
        XCTAssertTrue(expected.insetBy(dx: -0.01, dy: -0.01).contains(path.bounds),
                      "le lauburu s'inscrit dans son cercle (Ø \(2 * radius) pt) — bounds \(path.bounds)")
        // Poids optique §5.1 : ~70 % du canvas.
        XCTAssertEqual(path.bounds.width / MenuBarGlyphDrawing.canvas, 0.69, accuracy: 0.03)
    }

    func testFourFoldRotationalSymmetry() {
        let rep = rasterize(MenuBarGlyphDrawing.image(template: true))
        let side = Self.side
        var totalDiff: CGFloat = 0
        var maxDiff: CGFloat = 0
        for x in 0..<side {
            for y in 0..<side {
                let a = rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
                // Rotation de 90° autour du centre du bitmap : (x, y) → (y, side−1−x).
                let b = rep.colorAt(x: y, y: side - 1 - x)?.alphaComponent ?? 0
                let diff = abs(a - b)
                totalDiff += diff
                maxDiff = max(maxDiff, diff)
            }
        }
        let meanDiff = totalDiff / CGFloat(side * side)
        XCTAssertLessThan(meanDiff, 0.01,
                          "4 bras identiques par rotations de 90° exactes (écart moyen \(meanDiff))")
        XCTAssertLessThan(maxDiff, 0.5, "écart max toléré = anti-aliasing seul")
    }

    /// Chirality de la marque : tête en haut, queue balayant à GAUCHE vers le
    /// centre (les 4 têtes tournent en sens horaire). À la hauteur de la tête
    /// du bras supérieur, la masse déborde à gauche (demi-cercle extérieur
    /// R/2) et s'arrête plus court à droite (lobe R/4) — un miroir
    /// inverserait ces deux mesures.
    func testChiralityHeadsTurnClockwise() {
        let rep = rasterize(MenuBarGlyphDrawing.image(template: true))
        let headY = center + 0.75 * radius
        let left = alpha(rep, ptX: center - 0.4 * radius, ptY: headY)
        let right = alpha(rep, ptX: center + 0.4 * radius, ptY: headY)
        XCTAssertGreaterThan(left, 0.85,
                             "à gauche de l'axe, la tête du bras supérieur est pleine (demi-cercle extérieur)")
        XCTAssertLessThan(right, 0.15,
                          "à droite, au-delà du lobe R/4 : vide — un lauburu en miroir aurait de l'encre ici")
        // La queue du bras supérieur plonge vers le centre par la gauche.
        let tail = alpha(rep, ptX: center - 0.34 * radius, ptY: center + 0.25 * radius)
        XCTAssertGreaterThan(tail, 0.85, "croissant de queue présent à gauche, près du centre")
    }

    func testInkCoverageMatchesClassicConstruction() {
        // Aire théorique du lauburu classique plein : 4 bras × πR²/8 = πR²/2,
        // soit ≈ 19 % du canvas 18 × 18 — le poids d'encre de l'ancien glyphe.
        let rep = rasterize(MenuBarGlyphDrawing.image(template: true))
        let side = Self.side
        var ink: CGFloat = 0
        for x in 0..<side {
            for y in 0..<side {
                ink += rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
            }
        }
        let coverage = ink / CGFloat(side * side)
        let expected = (.pi * radius * radius / 2) / pow(MenuBarGlyphDrawing.canvas, 2)
        XCTAssertEqual(coverage, expected, accuracy: 0.02,
                       "couverture \(coverage) vs théorie \(expected)")
    }

    // MARK: - États

    func testProcessingDotRendersUnderGlyph() {
        let withDot = rasterize(MenuBarGlyphDrawing.image(
            template: false, dotAlpha: 1, dotColor: .systemRed
        ))
        let idle = rasterize(MenuBarGlyphDrawing.image(template: true))
        let dotCenter = MenuBarGlyphDrawing.dotRect
        let x = dotCenter.midX, y = dotCenter.midY
        XCTAssertGreaterThan(alpha(withDot, ptX: x, ptY: y), 0.85, "point de traitement présent")
        XCTAssertLessThan(alpha(idle, ptX: x, ptY: y), 0.15, "au repos : pas de point")
    }

    func testErrorBadgeRendersTopRightClearOfGlyph() {
        let withBadge = rasterize(MenuBarGlyphDrawing.image(template: false, badgeColor: .systemOrange))
        let idle = rasterize(MenuBarGlyphDrawing.image(template: true))
        let badge = MenuBarGlyphDrawing.badgeRect
        XCTAssertGreaterThan(alpha(withBadge, ptX: badge.midX, ptY: badge.midY), 0.85)
        XCTAssertLessThan(alpha(idle, ptX: badge.midX, ptY: badge.midY), 0.15,
                          "le badge vit hors du cercle du lauburu (Ø 12,5 < coin 15…18)")
    }

    func testGlyphAlphaDrivesRecordingBreath() {
        let full = rasterize(MenuBarGlyphDrawing.image(template: false, tint: .red, glyphAlpha: 1))
        let half = rasterize(MenuBarGlyphDrawing.image(template: false, tint: .red, glyphAlpha: 0.5))
        let x = center - 0.4 * radius
        let y = center + 0.75 * radius
        XCTAssertEqual(alpha(full, ptX: x, ptY: y), 1.0, accuracy: 0.05)
        XCTAssertEqual(alpha(half, ptX: x, ptY: y), 0.5, accuracy: 0.05,
                       "la respiration Arnasa module l'opacité du lauburu teinté")
    }
}
