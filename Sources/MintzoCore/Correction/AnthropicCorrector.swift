import Foundation

/// Fournit la clé API Anthropic (BYOK). L'implémentation Keychain arrive avec l'UI
/// de réglages — injectable pour les tests et le développement.
public protocol KeyProviding: Sendable {
    /// - Returns: la clé API (`sk-ant-…`), ou lève si absente/inaccessible.
    func apiKey() throws -> String
}

/// Erreurs de la passe de correction cloud.
public enum AnthropicCorrectorError: Error, Sendable, Equatable {
    case missingAPIKey
    case invalidResponse
    case httpError(status: Int, message: String)
    /// L'API a répondu 200 mais a refusé de traiter (stop_reason `refusal`).
    case refused
}

/// Correction cloud BYOK via l'API Messages d'Anthropic (option « qualité max » /
/// secours quand le modèle local n'est pas téléchargé).
///
/// Choix pinnés ensemble et documentés :
/// - Modèle `claude-sonnet-4-6` (reco coût/qualité de notes/research/latxa-correction.md ;
///   ~0,5 ¢ / dictée de 100 mots).
/// - `temperature: 0` pour le déterminisme — accepté sur Sonnet 4.6 ; ATTENTION : les
///   modèles 2026 plus récents (Opus 4.7+/Sonnet 5) rejettent ce paramètre en 400 →
///   le retirer si `model` est mis à niveau.
public struct AnthropicCorrector: Corrector {
    public static let model = "claude-sonnet-4-6"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    private let keyProvider: any KeyProviding
    private let session: URLSession
    private let protectedWords: [String]

    /// - Parameters:
    ///   - keyProvider: source de la clé API (Keychain en prod, stub en test).
    ///   - session: injectable pour les tests (URLProtocol mock) — `.shared` par défaut.
    ///   - protectedWords: graphies du dictionnaire personnalisé, injectées
    ///     dans le prompt système (même section que la correction locale).
    public init(
        keyProvider: any KeyProviding,
        session: URLSession = .shared,
        protectedWords: [String] = []
    ) {
        self.keyProvider = keyProvider
        self.session = session
        self.protectedWords = protectedWords
    }

    public func correct(_ text: String, language: Language) async throws -> String {
        let key: String
        do {
            key = try keyProvider.apiKey()
        } catch {
            throw AnthropicCorrectorError.missingAPIKey
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(
            MessagesRequest(
                model: Self.model,
                maxTokens: CorrectionPrompt.maxTokens(forInput: text),
                temperature: 0,
                system: CorrectionPrompt.system(for: language, protectedWords: protectedWords),
                messages: [.init(role: "user", content: text)]
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicCorrectorError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?
                .error.message ?? String(decoding: data.prefix(200), as: UTF8.self)
            throw AnthropicCorrectorError.httpError(status: http.statusCode, message: message)
        }

        guard let body = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            throw AnthropicCorrectorError.invalidResponse
        }
        if body.stopReason == "refusal" {
            throw AnthropicCorrectorError.refused
        }
        // content est une liste de blocs polymorphes — on ne lit que les blocs texte.
        let output = body.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !output.isEmpty else { throw AnthropicCorrectorError.invalidResponse }
        return output
    }

    // MARK: - Wire types (API Messages)

    private struct MessagesRequest: Encodable {
        let model: String
        let maxTokens: Int
        let temperature: Double
        let system: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: String
        }

        enum CodingKeys: String, CodingKey {
            case model, temperature, system, messages
            case maxTokens = "max_tokens"
        }
    }

    private struct MessagesResponse: Decodable {
        let content: [Block]
        let stopReason: String?

        struct Block: Decodable {
            let type: String
            let text: String?
        }

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct APIErrorEnvelope: Decodable {
        let error: APIError
        struct APIError: Decodable {
            let message: String
        }
    }
}
