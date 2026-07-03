import Foundation
import whisper

/// Erreurs du moteur de transcription.
public enum WhisperError: Error, Sendable, Equatable {
    case modelNotFound(String)
    case initializationFailed
    case transcriptionFailed(code: Int32)
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
}
