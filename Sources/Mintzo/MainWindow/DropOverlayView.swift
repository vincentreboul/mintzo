import SwiftUI

/// Overlay de drop fenêtre entière — design-language.md §6.3, amendement
/// v1.2 : matériau système (`.regularMaterial`), inset 12 pt, rayon 14 pt.
/// La bordure dashed 1.5 pt `MzGorri` (dash 6/4) est conservée — c'est
/// l'accent d'identité sur la couche fonctionnelle.
/// `arrow.down.doc` 28 pt + « Askatu hemen transkribatzeko » 15 pt Medium.
struct DropOverlayView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
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
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .allowsHitTesting(false)
    }
}
