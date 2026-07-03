import SwiftUI
import MintzoCore

// File d'attente de transcription de fichiers — design-language.md §6.3,
// amendement v1.2 : rangées natives dans une `Section` de la `List`
// (l'en-tête est posé par `HistoryListView`), progression `ProgressView`
// système teintée par l'accent. Alimentée par FileTranscriptionQueue (App/)
// via le protocole QueueDisplaying : zain → progression par étapes →
// done (retiré ~0,6 s) ou erreur (systemRed, 10 s).

/// Un fichier dans la file de transcription.
struct QueueItem: Identifiable, Equatable, Sendable {
    var id = UUID()
    var nomFichier: String
    /// Progression 0…1 ; nil = pas commencé (« zain »).
    var progress: Double?
    /// Durée audio détectée, en secondes (nil si pas encore sondée).
    var duree: TimeInterval?
    var langue: Transcription.Langue?
    /// Message d'échec court — l'item passe en rendu erreur (systemRed §2.3)
    /// et reste 10 s dans la file avant de disparaître.
    var erreur: String?
}

/// Source d'affichage de la file d'attente (câblage vague 3).
/// Implémentation attendue : classe `@Observable` pour que la section
/// se rafraîchisse d'elle-même.
@MainActor
protocol QueueDisplaying: AnyObject {
    var items: [QueueItem] { get }
}

/// Rangée d'un fichier en file : nom SF 13 Medium, statut à droite
/// (monospacedDigit), progression native. Couleurs système — la file est
/// de la machinerie, pas une surface de lecture.
struct QueueRowView: View {
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if item.erreur != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .accessibilityHidden(true)
                }
                Text(item.nomFichier)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(statusLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(item.erreur == nil
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(Color(nsColor: .systemRed)))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if item.erreur == nil, let progress = item.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        if let erreur = item.erreur { return erreur }
        guard item.progress != nil else { return MzL10n.queueWaiting }
        var parts: [String] = []
        if let duree = item.duree { parts.append(MzFormat.duree(duree)) }
        if let langue = item.langue, langue != .auto { parts.append(langue.rawValue) }
        return parts.isEmpty ? MzL10n.queueWaiting : parts.joined(separator: " · ")
    }
}

/// Barre de progression 2 pt : rail `MzHairline`, remplissage `MzGorri` (§6.3).
/// Conservée pour les surfaces éditoriales qui en dépendent (onboarding) —
/// la file d'attente de la fenêtre principale utilise `ProgressView` natif.
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
