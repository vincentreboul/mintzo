import Foundation
import Security

/// Erreurs typées du stockage Keychain.
public enum KeychainKeyStoreError: Error, LocalizedError, Sendable, Equatable {
    /// Aucune clé enregistrée pour ce service.
    case notFound
    /// L'item existe mais son contenu n'est pas décodable en UTF-8.
    case unexpectedData
    /// Erreur Security framework (status brut pour le diagnostic).
    case osStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Aucune clé API dans le trousseau"
        case .unexpectedData:
            return "Contenu du trousseau illisible"
        case .osStatus(let status):
            return "Erreur trousseau (OSStatus \(status))"
        }
    }
}

/// Stockage de la clé API Anthropic (BYOK) dans le trousseau macOS —
/// implémentation `KeyProviding` consommée par `AnthropicCorrector`.
///
/// Item `kSecClassGenericPassword` sur le trousseau de session (login) :
/// service « eus.mintzo.anthropic-key », compte « anthropic ». La clé ne
/// transite jamais par UserDefaults ni par un fichier. Service/compte
/// injectables pour les tests (service de test nettoyé après chaque cas).
public struct KeychainKeyStore: KeyProviding {

    public static let defaultService = "eus.mintzo.anthropic-key"
    public static let defaultAccount = "anthropic"

    private let service: String
    private let account: String

    public init(
        service: String = KeychainKeyStore.defaultService,
        account: String = KeychainKeyStore.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    // MARK: - KeyProviding

    /// Clé API (`sk-ant-…`), ou lève `KeychainKeyStoreError.notFound`.
    public func apiKey() throws -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                throw KeychainKeyStoreError.unexpectedData
            }
            return key
        case errSecItemNotFound:
            throw KeychainKeyStoreError.notFound
        default:
            throw KeychainKeyStoreError.osStatus(status)
        }
    }

    // MARK: - Écriture

    /// Enregistre (ou remplace) la clé. Une clé vide équivaut à `delete()`.
    public func set(_ key: String) throws {
        guard !key.isEmpty else {
            try delete()
            return
        }
        let data = Data(key.utf8)

        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Mintzo — Anthropic API"
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainKeyStoreError.osStatus(addStatus)
            }
        default:
            throw KeychainKeyStoreError.osStatus(updateStatus)
        }
    }

    /// Supprime la clé. Idempotent : silencieux si rien n'est enregistré.
    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainKeyStoreError.osStatus(status)
        }
    }

    /// Lecture non levante pour l'UI (champ pré-rempli, état « clé enregistrée »).
    public func storedKey() -> String? {
        try? apiKey()
    }

    // MARK: - Interne

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
