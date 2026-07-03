import SwiftUI
import MintzoCore

/// Vue détail d'une transcription — design-language.md §6.3.
/// Corps New York 16/26, mesure max 640 pt, sélectionnable.
/// Toggle discret « jatorrizkoa / zuzendua » (segmented 11 pt) seulement
/// si un texte corrigé existe.
struct TranscriptionDetailView: View {

    private enum Version: Hashable {
        case jatorrizkoa, zuzendua
    }

    let transcription: Transcription
    @State private var version: Version

    init(transcription: Transcription) {
        self.transcription = transcription
        // Par défaut on montre ce que l'utilisateur a réellement collé :
        // le corrigé s'il existe, sinon le brut.
        _version = State(initialValue: transcription.texteCorrige == nil ? .jatorrizkoa : .zuzendua)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if transcription.texteCorrige != nil {
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
    }

    private var displayedText: String {
        switch version {
        case .jatorrizkoa: transcription.texteBrut
        case .zuzendua: transcription.texteCorrige ?? transcription.texteBrut
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
}
