import Foundation
import Observation

/// Une règle de remplacement du dictionnaire : « entendu » → « voulu ».
/// Ex. whisper entend « mine tso », l'utilisateur veut « Mintzo ».
public struct VocabularyReplacement: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Texte tel que le moteur le produit (détection insensible à la casse).
    public var heard: String
    /// Texte voulu, inséré VERBATIM (sa casse est préservée telle que saisie).
    public var replacement: String

    public init(id: UUID = UUID(), heard: String, replacement: String) {
        self.id = id
        self.heard = heard
        self.replacement = replacement
    }
}

/// Dictionnaire personnalisé (à la SuperWhisper « Vocabulary ») — 100 % local.
///
/// Deux listes :
/// - **mots** : noms propres / graphies à respecter (« Bitwip », « Maite »,
///   lieux…) — injectés dans le prompt whisper et le prompt de correction ;
/// - **remplacements** : paires « entendu → voulu » appliquées en post-pass
///   déterministe après la correction (voir `VocabularyPostPass`).
///
/// `@MainActor` + `@Observable` : l'UI des Réglages observe directement les
/// listes (pattern natif SwiftUI), et les consommateurs hors main actor
/// (`TranscriptionService`) lisent via `await` — la classe est Sendable par
/// isolation. Persistance JSON à chaque mutation (fichier atomique, chemin
/// injectable pour les tests) : `~/Library/Application Support/Mintzo/vocabulary.json`.
@MainActor
@Observable
public final class VocabularyStore {

    public private(set) var words: [String] = []
    public private(set) var replacements: [VocabularyReplacement] = []

    @ObservationIgnored private let fileURL: URL

    /// Format du fichier sur disque — versionné pour d'éventuelles migrations.
    private struct FileFormat: Codable {
        var version: Int = 1
        var words: [String] = []
        var replacements: [VocabularyReplacement] = []
    }

    /// - Parameter fileURL: emplacement du JSON (injectable pour les tests).
    ///   Fichier absent ou illisible → listes vides, jamais d'erreur (le
    ///   dictionnaire ne doit jamais empêcher l'app de démarrer).
    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    /// Emplacement standard : `~/Library/Application Support/Mintzo/vocabulary.json`.
    public static func standard() -> VocabularyStore {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return VocabularyStore(
            fileURL: support
                .appendingPathComponent("Mintzo", isDirectory: true)
                .appendingPathComponent("vocabulary.json")
        )
    }

    // MARK: - Mots (graphies à respecter)

    /// Ajoute un mot (trimé). Refusé : vide, ou doublon (comparaison
    /// insensible à la casse). - Returns: `true` si ajouté.
    @discardableResult
    public func addWord(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !words.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }
        words.append(trimmed)
        save()
        return true
    }

    public func removeWord(_ word: String) {
        let before = words.count
        words.removeAll { $0 == word }
        if words.count != before { save() }
    }

    // MARK: - Remplacements (« entendu → voulu »)

    /// Ajoute une règle (champs trimés). Refusé : « entendu » vide, cible
    /// vide (un remplacement vide effacerait du texte dicté — interdit), ou
    /// « entendu » déjà présent (insensible à la casse — l'ordre d'application
    /// resterait ambigu). - Returns: `true` si ajouté.
    @discardableResult
    public func addReplacement(heard: String, replacement: String) -> Bool {
        let heardTrimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementTrimmed = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heardTrimmed.isEmpty, !replacementTrimmed.isEmpty else { return false }
        guard !replacements.contains(where: {
            $0.heard.caseInsensitiveCompare(heardTrimmed) == .orderedSame
        }) else { return false }
        replacements.append(
            VocabularyReplacement(heard: heardTrimmed, replacement: replacementTrimmed)
        )
        save()
        return true
    }

    public func removeReplacement(id: UUID) {
        let before = replacements.count
        replacements.removeAll { $0.id == id }
        if replacements.count != before { save() }
    }

    // MARK: - Persistance

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return } // premier lancement
        do {
            let file = try JSONDecoder().decode(FileFormat.self, from: data)
            words = file.words
            replacements = file.replacements
        } catch {
            NSLog("Mintzo: vocabulary.json illisible (%@) — dictionnaire repris à vide",
                  error.localizedDescription)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(
                FileFormat(words: words, replacements: replacements)
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Écriture ratée : l'état en mémoire reste correct pour la session,
            // signalé au log — jamais bloquant pour la dictée.
            NSLog("Mintzo: écriture de vocabulary.json échouée — %@", error.localizedDescription)
        }
    }
}
