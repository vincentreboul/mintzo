import Foundation
import whisper

/// Erreurs du moteur de transcription.
public enum WhisperError: Error, Sendable, Equatable {
    case modelNotFound(String)
    case initializationFailed
    case transcriptionFailed(code: Int32)
    /// Trop peu d'audio pour une détection de langue fiable (< ~0,5 s).
    case insufficientAudioForDetection
    case languageDetectionFailed(code: Int32)
}

/// Résultat d'une détection de langue.
public struct LanguageDetection: Sendable, Equatable {
    /// Code ISO 639-1 du gagnant (ex. « eu », « fr »).
    public let language: String
    /// Probabilité du gagnant. Si la détection était restreinte à des
    /// candidats, elle est renormalisée parmi eux (eu vs fr : P(eu)+P(fr)=1) —
    /// bien plus discriminante qu'une probabilité brute sur ~99 langues.
    public let confidence: Float

    public init(language: String, confidence: Float) {
        self.language = language
        self.confidence = confidence
    }
}

/// Wrapper Swift autour de l'API C de whisper.cpp.
///
/// Modélisé en `actor` : le contexte whisper (`whisper_context *`) n'est pas
/// thread-safe, l'isolation d'acteur sérialise donc tous les accès — pas besoin
/// de `@unchecked Sendable` ni de lock manuel. `whisper_full` est un appel
/// bloquant : il occupe le thread de l'executor pendant la transcription,
/// acceptable pour la V1 (une seule transcription à la fois par design).
public actor WhisperEngine {
    /// `nonisolated(unsafe)` requis pour `whisper_free` dans le deinit (nonisolated en
    /// Swift 6). Sûr : `ctx` est un `let` jamais exposé, tous les appels whisper passent
    /// par l'isolation de l'acteur, et le deinit ne s'exécute qu'après la dernière
    /// référence — aucun accès concurrent possible à ce moment-là.
    private nonisolated(unsafe) let ctx: OpaquePointer

    /// Charge un modèle ggml (ex. `ggml-tiny.bin`) depuis le disque.
    public init(modelPath: URL) throws {
        let path = modelPath.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw WhisperError.modelNotFound(path)
        }
        let cparams = whisper_context_default_params()
        guard let ctx = whisper_init_from_file_with_params(path, cparams) else {
            throw WhisperError.initializationFailed
        }
        self.ctx = ctx
    }

    deinit {
        whisper_free(ctx)
    }

    /// Transcrit des échantillons PCM float32 mono 16 kHz.
    /// - Parameters:
    ///   - samples: audio PCM normalisé [-1, 1], mono, 16 000 Hz.
    ///   - language: code langue ISO 639-1 forcé (ex. "fr", "eu") ; `nil` = auto-détection.
    /// - Returns: le texte transcrit, segments concaténés.
    public func transcribe(samples: [Float], language: String?) async throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.no_timestamps = true
        params.translate = false
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))

        let status = Self.withOptionalCString(language) { langPtr -> Int32 in
            params.language = langPtr
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
            }
        }
        guard status == 0 else {
            throw WhisperError.transcriptionFailed(code: status)
        }

        var text = ""
        for i in 0..<whisper_full_n_segments(ctx) {
            if let segment = whisper_full_get_segment_text(ctx, i) {
                text += String(cString: segment)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Exécute `body` avec un pointeur C valide pendant toute la durée de l'appel
    /// (ou `nil` si `string` est nil) — évite un pointeur pendouillant dans les params.
    private static func withOptionalCString<R>(
        _ string: String?,
        _ body: (UnsafePointer<CChar>?) -> R
    ) -> R {
        guard let string else { return body(nil) }
        return string.withCString(body)
    }

    // MARK: - Détection de langue (§4.4 mode auto)

    /// Seuil minimal d'audio pour une détection (0,5 s à 16 kHz).
    public static let detectionMinimumSampleCount = 8_000

    /// Détecte la langue parlée dans des échantillons PCM (mono 16 kHz).
    ///
    /// API C vérifiée dans le whisper.h du xcframework :
    /// `whisper_pcm_to_mel(ctx, samples, n_samples, n_threads)` calcule le
    /// spectrogramme mel, puis `whisper_lang_auto_detect(ctx, offset_ms,
    /// n_threads, lang_probs)` retourne l'id de la langue dominante et remplit
    /// le tableau de probabilités (taille `whisper_lang_max_id() + 1`).
    ///
    /// - Parameters:
    ///   - samples: audio PCM normalisé [-1, 1], mono, 16 kHz (≥ 0,5 s).
    ///   - candidates: restreint la décision à ces langues (ex. ["eu", "fr"]) ;
    ///     vide = gagnant global parmi toutes les langues whisper.
    public func detectLanguage(
        samples: [Float],
        among candidates: [String] = []
    ) async throws -> LanguageDetection {
        guard samples.count >= Self.detectionMinimumSampleCount else {
            throw WhisperError.insufficientAudioForDetection
        }
        let threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))

        let melStatus = samples.withUnsafeBufferPointer { buffer in
            whisper_pcm_to_mel(ctx, buffer.baseAddress, Int32(buffer.count), threads)
        }
        guard melStatus == 0 else {
            throw WhisperError.languageDetectionFailed(code: melStatus)
        }

        var probs = [Float](repeating: 0, count: Int(whisper_lang_max_id()) + 1)
        let topID = probs.withUnsafeMutableBufferPointer { buffer in
            whisper_lang_auto_detect(ctx, 0, threads, buffer.baseAddress)
        }
        guard topID >= 0 else {
            throw WhisperError.languageDetectionFailed(code: topID)
        }

        guard !candidates.isEmpty else {
            let language = whisper_lang_str(topID).map { String(cString: $0) } ?? "??"
            return LanguageDetection(language: language, confidence: probs[Int(topID)])
        }

        // Décision restreinte aux candidats (produit : eu vs fr), probabilité
        // renormalisée entre eux — robuste même quand whisper hésite avec une
        // langue tierce proche (es, pt…).
        var best: (language: String, probability: Float)?
        var total: Float = 0
        for candidate in candidates {
            let id = candidate.withCString(whisper_lang_id)
            guard id >= 0, Int(id) < probs.count else { continue }
            let probability = probs[Int(id)]
            total += probability
            if probability > (best?.probability ?? -1) {
                best = (candidate, probability)
            }
        }
        guard let best, total > 0 else {
            throw WhisperError.languageDetectionFailed(code: -1)
        }
        return LanguageDetection(language: best.language, confidence: best.probability / total)
    }
}
