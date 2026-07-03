import SwiftUI

/// Overlay de drop fenêtre entière — design-language.md §6.3.
/// Inset 12 pt, rayon 14 pt, bordure dashed 1.5 pt `MzGorri` (dash 6/4),
/// `arrow.down.doc` 28 pt + « Askatu hemen transkribatzeko » 15 pt Medium.
/// Fallback macOS 15 : `MzPaper` à 92 % (le verre arrive avec macOS 26).
struct DropOverlayView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(MzColor.paper.opacity(0.92))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    MzColor.gorri,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28))
                    .foregroundStyle(MzColor.gorri)
                Text(MzL10n.dropHint)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MzColor.ink)
            }
        }
        .padding(12)
        .allowsHitTesting(false)
    }
}
