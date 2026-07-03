import SwiftUI
import MintzoCore

// File d'attente de transcription de fichiers — design-language.md §6.3.
// Placeholder d'affichage : le protocole est câblé au vrai moteur en vague 3.

/// Un fichier dans la file de transcription.
struct QueueItem: Identifiable, Equatable, Sendable {
    var id = UUID()
    var nomFichier: String
    /// Progression 0…1 ; nil = pas commencé (« zain »).
    var progress: Double?
    /// Durée audio détectée, en secondes (nil si pas encore sondée).
    var duree: TimeInterval?
    var langue: Transcription.Langue?
}

/// Source d'affichage de la file d'attente (câblage vague 3).
/// Implémentation attendue : classe `@Observable` pour que la section
/// se rafraîchisse d'elle-même.
@MainActor
protocol QueueDisplaying: AnyObject {
    var items: [QueueItem] { get }
}

/// Section épinglée en tête de liste, visible seulement si la file est active.
struct QueueSectionView: View {
    let items: [QueueItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(MzL10n.queueHeader(count: items.count))
                .font(MzFont.sectionHeader)
                .tracking(MzFont.sectionHeaderTracking)
                .foregroundStyle(MzColor.inkSecondary)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        MzHairlineDivider()
                    }
                    QueueRowView(item: item)
                }
            }
            .background(MzColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(MzColor.hairline, lineWidth: 0.5)
            }
        }
    }
}

private struct QueueRowView: View {
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.nomFichier)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MzColor.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(statusLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MzColor.inkSecondary)
            }
            if let progress = item.progress {
                MzProgressBar(fraction: progress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var statusLabel: String {
        guard item.progress != nil else { return MzL10n.queueWaiting }
        var parts: [String] = []
        if let duree = item.duree { parts.append(MzFormat.duree(duree)) }
        if let langue = item.langue, langue != .auto { parts.append(langue.rawValue) }
        return parts.isEmpty ? MzL10n.queueWaiting : parts.joined(separator: " · ")
    }
}

/// Barre de progression 2 pt : rail `MzHairline`, remplissage `MzGorri` (§6.3).
struct MzProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(MzColor.hairline)
                Capsule()
                    .fill(MzColor.gorri)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 2)
    }
}

/// Hairline 0.5 pt réels, inset 14 pt (§6.3 : entre cellules seulement).
struct MzHairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(MzColor.hairline)
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }
}
