import SwiftUI
import AppKit
import MintzoCore

/// Contenu d'une rangée d'historique — la surface de lecture (§6.3,
/// amendement v1.2) : extrait New York 15/22 (2 lignes max), ligne méta
/// SF 11 monospacedDigit, tag langue Gorri 12 %. La rangée elle-même est
/// native (`List` + `NavigationLink`) : aucun fond custom, la sélection et
/// le focus sont ceux du système. Au hover : bouton copier `doc.on.doc`
/// en trailing (fade 160 ms) qui devient `checkmark` `MzSuccess` 800 ms
/// après copie réelle ; clic droit : menu contextuel natif « Copier ».
struct HistoryCellView: View {
    let transcription: Transcription
    /// Termes à surligner (`MzGorri` 24 %) en mode recherche.
    var highlightTerms: [String] = []

    @State private var isHovered = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(excerpt)
                .font(MzFont.historyExcerpt)
                .lineSpacing(MzFont.historyExcerptLineSpacing)
                .foregroundStyle(MzColor.ink)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.trailing, 28) // réserve du bouton copier au hover
            metaLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .overlay(alignment: .trailing) {
            if isHovered {
                copyButton
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(MzMotion.micro) { isHovered = hovering }
        }
        .contextMenu {
            Button(MzL10n.copy, systemImage: "doc.on.doc", action: copy)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Extrait (surlignage recherche : MzGorri 24 %)

    private var excerpt: AttributedString {
        var attributed = AttributedString(transcription.texteAffiche)
        guard !highlightTerms.isEmpty else { return attributed }
        let plain = transcription.texteAffiche
        for term in highlightTerms where !term.isEmpty {
            var searchRange = plain.startIndex..<plain.endIndex
            while let found = plain.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            ) {
                if let attrRange = Range(found, in: attributed) {
                    attributed[attrRange].backgroundColor =
                        MzColor.gorri.opacity(MzOpacity.activeBorder)
                }
                searchRange = found.upperBound..<plain.endIndex
            }
        }
        return attributed
    }

    // MARK: - Ligne méta : `14:32 · 0:42 · EU · diktaketa`

    private var metaLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(MzFormat.heure(transcription.date)) · \(MzFormat.duree(transcription.dureeAudio))")
                .font(MzFont.historyMeta.monospacedDigit())
                .foregroundStyle(MzColor.inkSecondary)
            Text("·")
                .font(MzFont.historyMeta)
                .foregroundStyle(MzColor.inkSecondary)
            langueTag
            Text("·")
                .font(MzFont.historyMeta)
                .foregroundStyle(MzColor.inkSecondary)
            Text(sourceLabel)
                .font(MzFont.historyMeta)
                .foregroundStyle(MzColor.inkSecondary)
        }
    }

    /// Tag langue : small caps Semibold `MzGorri`, fond 12 %, rayon 4, padding 3×1.5.
    private var langueTag: some View {
        Text(transcription.langue.rawValue)
            .font(MzFont.historyMetaTag)
            .foregroundStyle(MzColor.gorri)
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(MzColor.gorri.opacity(MzOpacity.tint))
            )
    }

    private var sourceLabel: String {
        switch transcription.source {
        case .dictee: MzL10n.sourceDictee
        case .fichier: MzL10n.sourceFichier
        }
    }

    // MARK: - Copier (NSPasteboard réel)

    private var copyButton: some View {
        Button(action: copy) {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: justCopied ? .semibold : .regular))
                .foregroundStyle(justCopied ? MzColor.success : Color.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(justCopied ? MzL10n.copied : MzL10n.copy)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcription.texteAffiche, forType: .string)
        withAnimation(MzMotion.micro) { justCopied = true }
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(MzMotion.micro) { justCopied = false }
        }
    }
}
