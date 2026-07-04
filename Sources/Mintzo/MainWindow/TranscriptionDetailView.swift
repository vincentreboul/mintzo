import SwiftUI
import MintzoCore

/// Vue détail d'une transcription — design-language.md §6.3, amendement
/// v1.2 : c'est LA surface éditoriale — une page `MzPaper` dans une fenêtre
/// native. Corps New York 16/26, mesure max 640 pt, sélectionnable.
/// Toggle discret « jatorrizkoa / zuzendua » (segmented 11 pt) seulement
/// si un texte corrigé existe. Le chrome (retour, sous-titre) reste système.
///
/// Réécoute / relance : si l'entrée a conservé son audio, une surface de
/// lecture sobre (`MzSurface` + hairline) porte le lecteur — play/pause,
/// barre de progression 2 pt teintée Gorri, durées monospacedDigit — et le
/// menu « Berriz sortu » (`arrow.clockwise`) qui repasse l'audio dans le
/// pipeline complet et met l'entrée à jour EN PLACE.
struct TranscriptionDetailView: View {

    private enum Version: Hashable {
        case jatorrizkoa, zuzendua
    }

    private enum ReplayState: Equatable {
        case idle
        case working
        case failed(String)
    }

    @State private var current: Transcription
    @State private var version: Version
    /// Lecteur créé UNE fois avec la vue (aucun IO : le backend AVAudioPlayer
    /// n'est chargé qu'au premier play) — nil si l'entrée n'a pas d'audio
    /// présent sur le disque.
    @State private var player: AudioPlayerController?
    @State private var replayState: ReplayState = .idle
    @State private var confirmingDelete = false

    /// Store d'historique — présent en navigation réelle (autorise la
    /// suppression depuis le détail), nil dans les rendus QA isolés.
    private let store: HistoryStore?
    @Environment(\.dismiss) private var dismiss

    init(transcription: Transcription, store: HistoryStore? = nil) {
        self.store = store
        _current = State(initialValue: transcription)
        // Par défaut on montre ce que l'utilisateur a réellement collé :
        // le corrigé s'il existe, sinon le brut.
        _version = State(initialValue: transcription.texteCorrige == nil ? .jatorrizkoa : .zuzendua)
        if let path = transcription.audioPath, FileManager.default.fileExists(atPath: path) {
            _player = State(initialValue: AudioPlayerController(
                url: URL(fileURLWithPath: path),
                fallbackDuration: transcription.dureeAudio
            ))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let player {
                    audioBar(player)
                }
                if case .failed(let message) = replayState {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
                if current.texteCorrige != nil {
                    versionPicker
                }
                Text(displayedText)
                    .font(MzFont.transcriptBody)
                    .lineSpacing(MzFont.transcriptBodyLineSpacing)
                    .foregroundStyle(MzColor.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .background(MzColor.paper)
        .navigationSubtitle(
            "\(MzFormat.heure(current.date)) · \(MzFormat.duree(current.dureeAudio))"
        )
        .toolbar {
            // Suppression depuis le détail (une entrée = son texte + son audio).
            // Absent des rendus QA isolés (aucun store injecté).
            if store != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        confirmingDelete = true
                    } label: {
                        Label(MzL10n.delete, systemImage: "trash")
                    }
                    .help(MzL10n.delete)
                }
            }
        }
        .confirmationDialog(
            MzL10n.deleteOneConfirmTitle,
            isPresented: $confirmingDelete
        ) {
            Button(MzL10n.delete, role: .destructive) { deleteEntry() }
        } message: {
            Text(MzL10n.deleteOneConfirmMessage)
        }
        .onDisappear {
            // Un seul lecteur actif dans l'app, et jamais de lecture fantôme
            // après le retour à la liste.
            player?.stop()
        }
    }

    /// Supprime l'entrée (texte + audio conservé via `HistoryStore.delete`)
    /// puis revient à la liste, qui se rafraîchit par observation du store.
    private func deleteEntry() {
        player?.stop()
        if let id = current.id {
            try? store?.delete(id: id)
        }
        dismiss()
    }

    private var displayedText: String {
        switch version {
        case .jatorrizkoa: current.texteBrut
        case .zuzendua: current.texteCorrige ?? current.texteBrut
        }
    }

    private var versionPicker: some View {
        Picker("", selection: $version.animation(MzMotion.micro)) {
            Text(MzL10n.detailOriginal).font(.system(size: 11)).tag(Version.jatorrizkoa)
            Text(MzL10n.detailCorrige).font(.system(size: 11)).tag(Version.zuzendua)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: - Surface de lecture (réécoute + relance)

    private func audioBar(_ controller: AudioPlayerController) -> some View {
        HStack(spacing: 12) {
            playPauseButton(controller)
            Text(MzFormat.duree(controller.currentTime))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(MzColor.inkSecondary)
            progressBar(controller)
            Text(MzFormat.duree(displayedDuration(controller)))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(MzColor.inkSecondary)
            replayControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 640)
        .background(MzColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MzColor.hairline, lineWidth: 0.5)
        )
    }

    private func playPauseButton(_ controller: AudioPlayerController) -> some View {
        Button {
            controller.togglePlayPause()
        } label: {
            Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(controller.unavailable ? MzColor.inkTertiary : MzColor.ink)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(controller.unavailable)
        .accessibilityLabel(
            controller.state == .playing ? MzL10n.playerPause : MzL10n.playerPlay
        )
        .help(controller.state == .playing ? MzL10n.playerPause : MzL10n.playerPlay)
    }

    /// Barre de progression 2 pt — rail `MzHairline`, remplissage Gorri
    /// (§2.4 : 100 % pour une barre de progression), rien d'autre.
    private func progressBar(_ controller: AudioPlayerController) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(MzColor.hairline)
                Capsule()
                    .fill(MzColor.gorri)
                    .frame(width: max(0, geometry.size.width * controller.progress))
            }
            .frame(height: 2)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 20)
        .frame(minWidth: 80)
    }

    /// Durée affichée : celle du fichier chargé, sinon celle de l'entrée.
    private func displayedDuration(_ controller: AudioPlayerController) -> TimeInterval {
        controller.duration > 0 ? controller.duration : current.dureeAudio
    }

    // MARK: - Relance

    @ViewBuilder
    private var replayControl: some View {
        if replayState == .working {
            // Spinner discret À LA PLACE du menu : une seule relance à la fois.
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        } else {
            Menu {
                Button(MzL10n.replayAuto) { replay(language: nil) }
                Button(MzL10n.replayEU) { replay(language: .basque) }
                Button(MzL10n.replayFR) { replay(language: .french) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MzColor.ink)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(MzL10n.replayMenu)
            .help(MzL10n.replayMenu)
        }
    }

    private func replay(language: Language?) {
        guard replayState != .working, let service = ReplayService.shared else { return }
        replayState = .working
        let entry = current
        Task { @MainActor in
            let result = await service.replay(entry, language: language)
            switch result {
            case .success(let updated):
                withAnimation(MzMotion.micro) {
                    current = updated
                    version = updated.texteCorrige == nil ? .jatorrizkoa : .zuzendua
                    replayState = .idle
                }
            case .failure(let failure):
                withAnimation(MzMotion.micro) {
                    replayState = .failed(Self.message(for: failure))
                }
            }
        }
    }

    private static func message(for failure: ReplayService.Failure) -> String {
        switch failure {
        case .modelMissing: MzL10n.replayModelMissing
        case .noAudio, .audioUnreadable: MzL10n.replayAudioUnreadable
        case .noText: MzL10n.queueNoText
        case .saveFailed: MzL10n.queueHistoryWriteFailed
        case .transcriptionFailed: MzL10n.replayFailed
        }
    }
}
