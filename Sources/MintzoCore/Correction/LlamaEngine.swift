import Foundation
import llama

/// Erreurs du moteur LLM local.
public enum LlamaError: Error, Sendable, Equatable {
    case modelNotFound(String)
    case initializationFailed
    case contextCreationFailed
    case engineUnloaded
    case tokenizationFailed
    case decodeFailed(code: Int32)
}

/// Wrapper Swift autour de l'API C de llama.cpp (xcframework précompilé, build pinné
/// dans scripts/fetch-llama-xcframework.sh).
///
/// Modélisé en `actor` (même pattern que `WhisperEngine`) : le contexte llama n'est pas
/// thread-safe, l'isolation d'acteur sérialise tous les accès. `llama_decode` est un
/// appel bloquant : il occupe le thread de l'executor pendant la génération — acceptable
/// pour la V1 (une correction à la fois par design).
///
/// Cycle de vie : `init(modelPath:)` charge le modèle (bloquant, quelques secondes pour
/// un 4B Q4), `unload()` libère explicitement la mémoire (~2,5 Go pour Latxa 4B Q4_K_M),
/// le `deinit` libère ce qui resterait.
public actor LlamaEngine {
    /// `nonisolated(unsafe)` requis pour la libération dans le deinit (nonisolated en
    /// Swift 6). Sûr : les pointeurs ne sont jamais exposés, tous les appels llama
    /// passent par l'isolation de l'acteur, et le deinit ne s'exécute qu'après la
    /// dernière référence — aucun accès concurrent possible à ce moment-là.
    private nonisolated(unsafe) var model: OpaquePointer?
    private nonisolated(unsafe) var ctx: OpaquePointer?
    private nonisolated(unsafe) var sampler: UnsafeMutablePointer<llama_sampler>?

    private let contextSize: UInt32
    private let batchSize: UInt32

    /// Initialise le backend ggml une seule fois par process.
    private static let backendOnce: Void = llama_backend_init()

    /// Charge un modèle GGUF depuis le disque.
    /// - Parameters:
    ///   - modelPath: chemin du fichier `.gguf` (poids INSTRUCT, ex. Latxa-Qwen3-VL-4B Q4_K_M).
    ///   - contextSize: taille du contexte en tokens (défaut 4096 — large pour une dictée,
    ///     borne la mémoire du KV cache).
    public init(modelPath: URL, contextSize: UInt32 = 4096) throws {
        _ = Self.backendOnce

        let path = modelPath.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaError.modelNotFound(path)
        }

        var mparams = llama_model_default_params()
        // Négatif = toutes les couches offloadées (Metal sur Apple Silicon).
        mparams.n_gpu_layers = -1
        guard let model = llama_model_load_from_file(path, mparams) else {
            throw LlamaError.initializationFailed
        }

        let batch: UInt32 = 512
        var cparams = llama_context_default_params()
        cparams.n_ctx = contextSize
        cparams.n_batch = batch
        let threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))
        cparams.n_threads = threads
        cparams.n_threads_batch = threads
        guard let ctx = llama_init_from_model(model, cparams) else {
            llama_model_free(model)
            throw LlamaError.contextCreationFailed
        }

        // Sampling déterministe : greedy pur (température 0), aucun aléa.
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        self.model = model
        self.ctx = ctx
        self.sampler = sampler
        self.contextSize = contextSize
        self.batchSize = batch
    }

    deinit {
        Self.release(model: model, ctx: ctx, sampler: sampler)
    }

    /// Libère explicitement le modèle et le contexte (idempotent). L'engine est
    /// inutilisable ensuite : tout `generate` lèvera `.engineUnloaded`.
    public func unload() {
        Self.release(model: model, ctx: ctx, sampler: sampler)
        model = nil
        ctx = nil
        sampler = nil
    }

    private static func release(
        model: OpaquePointer?, ctx: OpaquePointer?, sampler: UnsafeMutablePointer<llama_sampler>?
    ) {
        if let sampler { llama_sampler_free(sampler) }
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
    }

    /// Génère une complétion pour un couple (system, user) via le chat template du
    /// modèle, en greedy décodage. Chaque appel repart d'un état vierge (KV cache vidé).
    /// - Parameters:
    ///   - system: prompt système (consignes strictes de correction).
    ///   - user: message utilisateur (le texte à corriger).
    ///   - maxTokens: plafond de tokens générés (arrêt propre sur EOG sinon).
    /// - Returns: le texte généré, trimé.
    public func generate(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let model, let ctx, let sampler else { throw LlamaError.engineUnloaded }
        let vocab = llama_model_get_vocab(model)

        // 1. Prompt formaté via le chat template embarqué dans le GGUF
        //    (llama_chat_apply_template), fallback ChatML manuel si absent/inconnu.
        let prompt = Self.applyChatTemplate(model: model, system: system, user: user)

        // 2. Tokenisation.
        var tokens = try Self.tokenize(vocab: vocab, text: prompt)

        // 3. État vierge : on vide la mémoire (KV cache) du contexte.
        llama_memory_clear(llama_get_memory(ctx), true)
        llama_sampler_reset(sampler)

        // Garde : prompt + génération doivent tenir dans le contexte.
        let budget = Int(contextSize) - tokens.count - 1
        guard budget > 0 else { throw LlamaError.decodeFailed(code: -1) }

        // 4. Décodage du prompt (par morceaux de n_batch max).
        var offset = 0
        while offset < tokens.count {
            let chunk = min(Int(batchSize), tokens.count - offset)
            let rc = tokens.withUnsafeMutableBufferPointer { buf in
                llama_decode(ctx, llama_batch_get_one(buf.baseAddress! + offset, Int32(chunk)))
            }
            guard rc == 0 else { throw LlamaError.decodeFailed(code: rc) }
            offset += chunk
        }

        // 5. Boucle de génération greedy, arrêt sur EOG / maxTokens / contexte plein.
        var outBytes: [UInt8] = []
        var pieceBuf = [CChar](repeating: 0, count: 256)
        for step in 0..<min(maxTokens, budget) {
            var token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }

            let n = llama_token_to_piece(vocab, token, &pieceBuf, Int32(pieceBuf.count), 0, false)
            if n > 0 {
                pieceBuf.prefix(Int(n)).forEach { outBytes.append(UInt8(bitPattern: $0)) }
            }

            if step == min(maxTokens, budget) - 1 { break }
            let rc = llama_decode(ctx, llama_batch_get_one(&token, 1))
            guard rc == 0 else { throw LlamaError.decodeFailed(code: rc) }
        }

        return String(decoding: outBytes, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Helpers (statiques, pas d'état acteur)

    /// Applique le chat template du modèle (system + user, add_assistant=true).
    /// `llama_chat_apply_template` ne parse pas Jinja : il reconnaît une liste de
    /// gabarits connus (ChatML de Qwen3/SmolLM2 inclus). Fallback ChatML manuel sinon.
    private static func applyChatTemplate(
        model: OpaquePointer, system: String, user: String
    ) -> String {
        let fallback =
            "<|im_start|>system\n\(system)<|im_end|>\n"
            + "<|im_start|>user\n\(user)<|im_end|>\n"
            + "<|im_start|>assistant\n"

        guard let tmpl = llama_model_chat_template(model, nil) else { return fallback }

        let roles = [strdup("system"), strdup("user")]
        let contents = [strdup(system), strdup(user)]
        defer {
            roles.forEach { free($0) }
            contents.forEach { free($0) }
        }
        var messages: [llama_chat_message] = zip(roles, contents).map {
            llama_chat_message(role: $0, content: $1)
        }

        let hint = 2 * (system.utf8.count + user.utf8.count) + 1024
        var buf = [CChar](repeating: 0, count: hint)
        var written = llama_chat_apply_template(tmpl, &messages, messages.count, true, &buf, Int32(buf.count))
        if written > Int32(buf.count) {
            buf = [CChar](repeating: 0, count: Int(written) + 1)
            written = llama_chat_apply_template(tmpl, &messages, messages.count, true, &buf, Int32(buf.count))
        }
        guard written > 0 else { return fallback }
        let bytes = buf.prefix(Int(written)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Tokenise `text` (tokens spéciaux du template parsés, add_special géré par le vocab).
    private static func tokenize(vocab: OpaquePointer?, text: String) throws -> [llama_token] {
        let byteCount = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: byteCount + 32)
        var n = llama_tokenize(vocab, text, Int32(byteCount), &tokens, Int32(tokens.count), true, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, Int32(byteCount), &tokens, Int32(tokens.count), true, true)
        }
        guard n > 0 else { throw LlamaError.tokenizationFailed }
        return Array(tokens.prefix(Int(n)))
    }
}
