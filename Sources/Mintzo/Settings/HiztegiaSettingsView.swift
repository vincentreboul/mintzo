import SwiftUI
import MintzoCore

/// Onglet Hiztegia : dictionnaire personnalisé — deux sections (mots ;
/// remplacements « entendu → voulu »), ajout par champ + bouton, suppression
/// au survol, état vide sobre. Zéro emoji (SF Symbols seulement), microcopy §9.
struct HiztegiaSettingsView: View {
    let store: VocabularyStore

    @State private var newWord = ""
    @State private var newHeard = ""
    @State private var newWanted = ""
    @State private var hoveredWord: String?
    @State private var hoveredReplacementID: UUID?

    var body: some View {
        Form {
            wordsSection
            replacementsSection
        }
        .formStyle(.grouped)
        .frame(height: 460)
    }

    // MARK: - Mots (graphies à respecter)

    private var wordsSection: some View {
        Section {
            if store.words.isEmpty {
                emptyLine(SettingsStrings.vocabularyWordsEmpty)
            } else {
                ForEach(store.words, id: \.self) { word in
                    HStack(spacing: 8) {
                        Text(word)
                            .font(.system(size: 13))
                        Spacer()
                        deleteButton(visible: hoveredWord == word) {
                            store.removeWord(word)
                        }
                    }
                    .onHover { hovering in
                        hoveredWord = hovering ? word : (hoveredWord == word ? nil : hoveredWord)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(SettingsStrings.vocabularyWordPlaceholder, text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWord)
                Button(SettingsStrings.vocabularyAdd, action: addWord)
                    .controlSize(.small)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(SettingsStrings.vocabularyWordsSection)
        } footer: {
            footerLine(SettingsStrings.vocabularyWordsFooter)
        }
    }

    // MARK: - Remplacements (« entendu → voulu »)

    private var replacementsSection: some View {
        Section {
            if store.replacements.isEmpty {
                emptyLine(SettingsStrings.vocabularyReplacementsEmpty)
            } else {
                ForEach(store.replacements) { rule in
                    HStack(spacing: 8) {
                        Text(rule.heard)
                            .font(.system(size: 13))
                            .foregroundStyle(MzColor.inkSecondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MzColor.inkTertiary)
                        Text(rule.replacement)
                            .font(.system(size: 13))
                        Spacer()
                        deleteButton(visible: hoveredReplacementID == rule.id) {
                            store.removeReplacement(id: rule.id)
                        }
                    }
                    .onHover { hovering in
                        hoveredReplacementID = hovering
                            ? rule.id
                            : (hoveredReplacementID == rule.id ? nil : hoveredReplacementID)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(SettingsStrings.vocabularyHeardPlaceholder, text: $newHeard)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReplacement)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MzColor.inkTertiary)
                TextField(SettingsStrings.vocabularyWantedPlaceholder, text: $newWanted)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReplacement)
                Button(SettingsStrings.vocabularyAdd, action: addReplacement)
                    .controlSize(.small)
                    .disabled(
                        newHeard.trimmingCharacters(in: .whitespaces).isEmpty
                            || newWanted.trimmingCharacters(in: .whitespaces).isEmpty
                    )
            }
        } header: {
            Text(SettingsStrings.vocabularyReplacementsSection)
        } footer: {
            footerLine(SettingsStrings.vocabularyReplacementsFooter)
        }
    }

    // MARK: - Actions

    private func addWord() {
        if store.addWord(newWord) {
            newWord = ""
        }
    }

    private func addReplacement() {
        if store.addReplacement(heard: newHeard, replacement: newWanted) {
            newHeard = ""
            newWanted = ""
        }
    }

    // MARK: - Composants

    /// Croix de suppression, révélée au survol de la ligne (cliquable même
    /// invisible — la zone reste stable, pas de layout shift).
    private func deleteButton(visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(MzColor.inkTertiary)
        }
        .buttonStyle(.borderless)
        .opacity(visible ? 1 : 0)
        .accessibilityLabel(SettingsStrings.remove)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(MzColor.inkTertiary)
    }

    private func footerLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(MzColor.inkSecondary)
    }
}
