import Foundation
import MintzoCore

// Fabrique des correcteurs selon le réglage Zuzenketa (off / latxa / cloud).
// Latxa : le GGUF (~2,5 Go) est chargé PARESSEUSEMENT, hors main actor, à la
// première correction — jamais au lancement de l'app. Première passe à froid :
// le chargement peut consommer le budget de 10 s → repli texte brut, assumé.

/// Le modèle Latxa décrit comme entrée téléchargeable par `ModelManager`
/// (même pipeline download + SHA256 + install atomique que les Whisper).
/// Le fichier est stocké sous `<id>.bin` — llama.cpp identifie le GGUF par
/// ses magic bytes, pas par l'extension.
extension ModelCatalog {
    static let latxaCorrection: WhisperModel = {
        let entry = LatxaCatalog.default
        return WhisperModel(
            id: entry.id,
            displayName: entry.displayName,
            downloadURL: entry.url,
            sizeBytes: entry.sizeBytes,
            sha256: entry.sha256,
            role: .testing // hors catalogue Whisper : le rôle n'est pas consommé
        )
    }()
}

/// Charge le moteur Latxa à la première demande puis le réutilise (un seul
/// gros modèle de correction en RAM). `unload()` libère la mémoire.
actor LatxaEngineLoader {
    private let modelURL: URL
    private var engine: LlamaEngine?

    init(modelURL: URL) {
        self.modelURL = modelURL
    }

    func corrector(protectedWords: [String] = []) throws -> LatxaCorrector {
        if engine == nil {
            engine = try LlamaEngine(modelPath: modelURL)
        }
        guard let engine else { throw LlamaError.engineUnloaded }
        return LatxaCorrector(engine: engine, protectedWords: protectedWords)
    }

    func unload() {
        engine = nil
    }
}

/// Corrector qui matérialise le moteur Latxa au premier appel.
struct LazyLatxaCorrector: Corrector {
    let loader: LatxaEngineLoader
    /// Graphies du dictionnaire personnalisé (snapshot au départ de la passe).
    var protectedWords: [String] = []

    func correct(_ text: String, language: Language) async throws -> String {
        try await loader.corrector(protectedWords: protectedWords)
            .correct(text, language: language)
    }
}
