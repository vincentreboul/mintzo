// Mintzo — générateur d'icône app macOS (R2 : grille Apple avec marges)
// Canvas transparent ; squircle continu (style Apple) inset à 824/1024 du canvas,
// dégradé Gorri Etxea + glyphe caret-et-ondes (§5.1/§8 design-language.md)
// Build : swiftc -O -parse-as-library icon_gen.swift -o icon_gen
// Run   : ./icon_gen <outDir>

import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct Err: Error, CustomStringConvertible { let description: String }

// MARK: - Grille Apple : côté du squircle dans le canvas

/// 824/1024 ≈ 80.47 % du canvas (grille icône macOS Big Sur+).
/// 16 et 32 px : côtés calés à la main sur la grille pixel (marges entières → bords nets).
func contentSide(forCanvas s: CGFloat) -> CGFloat {
    if abs(s - 16) < 0.5 { return 12 }  // marge 2 px
    if abs(s - 32) < 0.5 { return 26 }  // marge 3 px
    return s * 824.0 / 1024.0           // 64→51.5, 128→103, 256→206, 512→412, 1024→824
}

// MARK: - RNG déterministe (bruit minéral reproductible)

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Bruit minéral : speckle blanc/noir, alpha moyen ~2.4 % (spec : 2-3 %, à peine perceptible).
func makeNoise(size: Int, seed: UInt64) -> CGImage? {
    var rng = SplitMix64(state: seed)
    var buf = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) {
        let r = rng.next()
        let white = (r & 1) == 1
        let a = UInt8((r >> 1) % 13) // 0..12 → moyenne 6/255 ≈ 2.4 %
        let p = i * 4
        if white { buf[p] = a; buf[p+1] = a; buf[p+2] = a } // premultiplied
        buf[p+3] = a
    }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return buf.withUnsafeMutableBytes { ptr -> CGImage? in
        guard let ctx = CGContext(data: ptr.baseAddress, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        return ctx.makeImage()
    }
}

// MARK: - Glyphe caret + ondes (§5.1, à l'échelle du squircle ; largeur = 55 % du squircle)

struct GlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for r in Self.rects(side: rect.width) {
            let radius = min(r.width, r.height) / 2
            p.addRoundedRect(in: r, cornerSize: CGSize(width: radius, height: radius))
        }
        return p
    }

    /// Canvas source 18 : caret 2×12 @x9 ; barres 2 de large, h7 @x±4.5, h4 @x±7.5.
    /// Glyphe = 17 unités de large → u = 0.55*side/17. Gap caret↔barre = 2.5u = 14.7 % (spec ≥ 8 %).
    /// Coordonnées locales au squircle (le squircle est lui-même centré dans le canvas).
    static func rects(side: CGFloat) -> [CGRect] {
        // Squircle 12 px (canvas 16) : glyphe SIMPLIFIÉ caret + barres intérieures,
        // gaps 1 px nets — la lisibilité prime sur la fidélité à cette taille.
        if abs(side - 12) < 0.5 {
            return [
                CGRect(x: 5, y: 3, width: 2, height: 6), // caret
                CGRect(x: 3, y: 4, width: 1, height: 4), // intérieures
                CGRect(x: 8, y: 4, width: 1, height: 4),
            ]
        }
        // Squircle 26 px (canvas 32) : 5 barres, bords verticaux calés grille pixel
        if abs(side - 26) < 0.5 {
            return [
                CGRect(x: 12, y: 8,  width: 2, height: 10), // caret
                CGRect(x: 8,  y: 10, width: 2, height: 6),  // intérieures
                CGRect(x: 16, y: 10, width: 2, height: 6),
                CGRect(x: 5,  y: 11, width: 2, height: 4),  // extérieures
                CGRect(x: 19, y: 11, width: 2, height: 4),
            ]
        }
        let u = 0.55 * side / 17
        let c = side / 2
        let w = 2 * u
        func bar(_ dx: CGFloat, _ hUnits: CGFloat) -> CGRect {
            let h = hUnits * u
            return CGRect(x: c + dx * u - w/2, y: c - h/2, width: w, height: h)
        }
        return [bar(0, 12), bar(-4.5, 7), bar(4.5, 7), bar(-7.5, 4), bar(7.5, 4)]
    }
}

// MARK: - Contenu du squircle (dimensionné par `side`, pas par le canvas)

struct IconContent: View {
    let side: CGFloat
    let noise: CGImage?

    private var gorriTop: Color    { Color(.sRGB, red: 0xA8/255.0, green: 0x32/255.0, blue: 0x26/255.0, opacity: 1) }
    private var gorriBottom: Color { Color(.sRGB, red: 0x8C/255.0, green: 0x28/255.0, blue: 0x20/255.0, opacity: 1) }
    private var paper: Color       { Color(.sRGB, red: 0xFA/255.0, green: 0xF9/255.0, blue: 0xF7/255.0, opacity: 1) }

    var body: some View {
        let squircle = RoundedRectangle(cornerRadius: 0.2237 * side, style: .continuous)
        ZStack {
            // Fond : dégradé vertical très retenu
            LinearGradient(colors: [gorriTop, gorriBottom], startPoint: .top, endPoint: .bottom)

            // Ombre interne haute, très légère (laque)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.10), location: 0.0),
                .init(color: .black.opacity(0.0),  location: 0.085),
                .init(color: .black.opacity(0.0),  location: 1.0),
            ], startPoint: .top, endPoint: .bottom)

            // Éclaircissement bas, discret
            LinearGradient(stops: [
                .init(color: .white.opacity(0.0),   location: 0.0),
                .init(color: .white.opacity(0.0),   location: 0.90),
                .init(color: .white.opacity(0.065), location: 1.0),
            ], startPoint: .top, endPoint: .bottom)

            // Liseré de bord biseauté : sombre en haut, clair en bas (effet laque, pas de gloss)
            squircle
                .inset(by: side * 0.006)
                .stroke(LinearGradient(colors: [.black.opacity(0.16), .white.opacity(0.14)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: side * 0.009)
                .blur(radius: side * 0.005)

            // Bruit minéral (squircle ≥ 100 px seulement — invisible/boue en dessous)
            if let noise, side >= 100 {
                Image(decorative: noise, scale: 1).interpolation(.none)
            }

            // Glyphe blanc papier, relief discret aux grandes tailles
            if side >= 50 {
                GlyphShape().fill(paper)
                    .shadow(color: .black.opacity(0.20), radius: side * 0.010, x: 0, y: side * 0.006)
            } else {
                GlyphShape().fill(paper)
            }
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .clipShape(squircle)
    }
}

// MARK: - Icône = squircle centré dans un canvas transparent (grille Apple)

struct IconView: View {
    let s: CGFloat // canvas px
    let noise: CGImage?
    var body: some View {
        IconContent(side: contentSide(forCanvas: s), noise: noise)
            .frame(width: s, height: s) // centre le squircle, marges transparentes
    }
}

// MARK: - I/O PNG + utilitaires QA

func writePNG(_ img: CGImage, _ path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { throw Err(description: "CGImageDestination failed: \(path)") }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { throw Err(description: "PNG finalize failed: \(path)") }
}

func scaleNearest(_ img: CGImage, factor: Int) throws -> CGImage {
    let w = img.width * factor, h = img.height * factor
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Err(description: "scale ctx") }
    ctx.interpolationQuality = .none
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let out = ctx.makeImage() else { throw Err(description: "scale makeImage") }
    return out
}

/// Buffer RGBA8 sRGB non-flippé : rangée 0 = haut de l'image.
func rgbaBuffer(_ img: CGImage) throws -> [UInt8] {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    try buf.withUnsafeMutableBytes { ptr in
        guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Err(description: "qa ctx") }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return buf
}

func pixel(_ buf: [UInt8], _ w: Int, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let p = (y * w + x) * 4
    return (Int(buf[p]), Int(buf[p+1]), Int(buf[p+2]), Int(buf[p+3]))
}

// MARK: - Main

@main
@MainActor
struct IconGen {
    static func main() throws {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        let iconsetDir = outDir + "/AppIcon.iconset"
        try FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        var images: [Int: CGImage] = [:]
        for px in sizes {
            let side = contentSide(forCanvas: CGFloat(px))
            let noise = side >= 100 ? makeNoise(size: Int(side), seed: 0x4D69_6E74_7A6F) : nil // "Mintzo"
            let renderer = ImageRenderer(content: IconView(s: CGFloat(px), noise: noise))
            renderer.scale = 1
            renderer.isOpaque = false
            guard let img = renderer.cgImage else { throw Err(description: "render \(px) failed") }
            guard img.width == px, img.height == px else {
                throw Err(description: "render \(px): got \(img.width)x\(img.height)")
            }
            images[px] = img
        }

        let entries: [(String, Int)] = [
            ("icon_16x16.png", 16),   ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),   ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),("icon_512x512@2x.png", 1024),
        ]
        for (name, px) in entries { try writePNG(images[px]!, iconsetDir + "/" + name) }

        try writePNG(images[1024]!, outDir + "/preview-1024.png")
        try writePNG(images[64]!,   outDir + "/preview-64.png")
        try writePNG(scaleNearest(images[16]!, factor: 8), outDir + "/preview-16.png")
        // QA internes (inspection confortable)
        try writePNG(scaleNearest(images[32]!, factor: 8), outDir + "/qa-32-x8.png")
        try writePNG(scaleNearest(images[64]!, factor: 4), outDir + "/qa-64-x4.png")

        try qaReport(images)
        print("OK — iconset écrit dans \(iconsetDir)")
    }

    static func qaReport(_ images: [Int: CGImage]) throws {
        let big = try rgbaBuffer(images[1024]!)
        let w = 1024
        print("=== QA programmatique (grille Apple 824/1024, marge 100 px @1024) ===")
        for (x, y) in [(3, 3), (1020, 3), (3, 1020), (1020, 1020)] {
            let p = pixel(big, w, x, y)
            print("coin canvas (\(x),\(y)) alpha=\(p.a) (attendu 0)")
        }
        for (x, y) in [(512, 1), (1, 512), (512, 1022), (1022, 512)] {
            let p = pixel(big, w, x, y)
            print("bord canvas (\(x),\(y)) alpha=\(p.a) (attendu 0 — marge transparente)")
        }
        for (x, y) in [(512, 105), (105, 512), (512, 918), (918, 512)] {
            let p = pixel(big, w, x, y)
            print("intérieur squircle (\(x),\(y)) alpha=\(p.a) (attendu 255)")
        }
        let top = pixel(big, w, 512, 140)
        let bottom = pixel(big, w, 512, 884)
        print(String(format: "fond haut ≈ #%02X%02X%02X (base A83226)", top.r, top.g, top.b))
        print(String(format: "fond bas  ≈ #%02X%02X%02X (base 8C2820)", bottom.r, bottom.g, bottom.b))
        let center = pixel(big, w, 512, 512)
        print(String(format: "centre (caret) ≈ #%02X%02X%02X (attendu ~FAF9F7)", center.r, center.g, center.b))

        // Carte ASCII du rendu 16 px : '#' = glyphe franc, '+' = AA, '.' = fond, ' ' = transparent
        let s16 = try rgbaBuffer(images[16]!)
        print("--- 16 px map (squircle 12 px, marge 2 px) ---")
        for y in 0..<16 {
            var row = ""
            for x in 0..<16 {
                let p = pixel(s16, 16, x, y)
                if p.a < 20 { row += " " }
                else if p.g > 140 { row += "#" }
                else if p.g > 90 { row += "+" }
                else { row += "." }
            }
            print("|" + row + "|")
        }
        let side = 824.0
        let u = 0.55 * side / 17.0
        print(String(format: "squircle: %.0f px (%.2f %% canvas) ; glyphe: %.0f px (55 %% squircle) ; gap caret↔barre = %.1f %% glyphe (spec ≥ 8 %%)",
                     side, 100 * side / 1024, 17 * u, 100 * 2.5 / 17))
    }
}
