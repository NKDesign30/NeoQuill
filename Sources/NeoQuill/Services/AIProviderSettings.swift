import Foundation
import Security

enum AISummaryProvider: String, CaseIterable, Codable, Identifiable {
    case claudeCLI = "claude_cli"
    case openAICompatible = "openai_compatible"
    case anthropicAPI = "anthropic_api"
    case ollama = "ollama"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCLI:
            return "Claude CLI (lokaler Login)"
        case .openAICompatible:
            return "OpenAI-kompatibel"
        case .anthropicAPI:
            return "Anthropic API (Claude)"
        case .ollama:
            return "Ollama (lokal)"
        }
    }

    /// Braucht der Provider einen API-Key in der Keychain?
    var requiresAPIKey: Bool {
        switch self {
        case .claudeCLI, .ollama:
            return false
        case .openAICompatible, .anthropicAPI:
            return true
        }
    }
}

/// Welcher Keychain-Eintrag ein Provider-Key belegt. Ein Store, mehrere Scopes,
/// statt pro Provider eine eigene Store-Klasse.
enum AIProviderKeyScope {
    case openAICompatible
    case anthropic

    var keychainService: String {
        switch self {
        case .openAICompatible:
            return "com.neon.quill.ai.openai-compatible"
        case .anthropic:
            return "com.neon.quill.ai.anthropic"
        }
    }
}

struct OpenAICompatibleSummaryConfig: Equatable {
    let baseURL: URL
    let model: String
    let apiKey: String

    var chatCompletionsURL: URL {
        baseURL.appending(path: "chat/completions")
    }
}

struct AnthropicSummaryConfig: Equatable {
    let baseURL: URL
    let model: String
    let apiKey: String

    var messagesURL: URL {
        baseURL.appending(path: "messages")
    }
}

protocol AIProviderSecretPersisting {
    func apiKey(for scope: AIProviderKeyScope) -> String?
    func setAPIKey(_ apiKey: String, for scope: AIProviderKeyScope) throws
    func clearAPIKey(for scope: AIProviderKeyScope)
}

final class AIProviderSecretStore: AIProviderSecretPersisting {
    private let account = "api-key"

    func apiKey(for scope: AIProviderKeyScope) -> String? {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: scope.keychainService as CFString,
            kSecAttrAccount: account as CFString,
            kSecReturnData: kCFBooleanTrue,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setAPIKey(_ apiKey: String, for scope: AIProviderKeyScope) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else { return }

        let baseQuery: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: scope.keychainService as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        var insert = baseQuery
        insert[kSecValueData] = data as CFData
        insert[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "AIProviderSecretStore",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain-Speicherung fehlgeschlagen (\(status))"]
            )
        }
    }

    func clearAPIKey(for scope: AIProviderKeyScope) {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: scope.keychainService as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AIProviderSettings {
    // Neutraler Default: der OpenAI-kompatible Pfad ist der generische BYOK-Weg
    // (eigener Key/Endpoint) statt einer Annahme über lokal installierte Tools.
    static let defaultProvider = AISummaryProvider.openAICompatible.rawValue
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-5.1"
    static let defaultAnthropicBaseURL = "https://api.anthropic.com/v1"
    static let defaultAnthropicModel = "claude-haiku-4-5"
    static let defaultOllamaBaseURL = "http://localhost:11434/v1"
    static let defaultOllamaModel = "llama3.1"

    static func selectedProvider(defaults: UserDefaults = .standard) -> AISummaryProvider {
        let raw = defaults.stringOr(AppSettings.aiSummaryProvider, default: defaultProvider)
        return AISummaryProvider(rawValue: raw) ?? .claudeCLI
    }

    static func openAICompatibleConfig(
        defaults: UserDefaults = .standard,
        secretStore: AIProviderSecretPersisting = AIProviderSecretStore()
    ) -> OpenAICompatibleSummaryConfig? {
        let rawBaseURL = defaults.stringOr(AppSettings.aiSummaryBaseURL, default: defaultOpenAIBaseURL)
        let rawModel = defaults.stringOr(AppSettings.aiSummaryModel, default: defaultOpenAIModel)
        let normalizedBaseURL = normalizeBaseURL(rawBaseURL)
        guard let baseURL = URL(string: normalizedBaseURL),
              !rawModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let apiKey = secretStore.apiKey(for: .openAICompatible),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return OpenAICompatibleSummaryConfig(
            baseURL: baseURL,
            model: rawModel.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey
        )
    }

    static func anthropicConfig(
        defaults: UserDefaults = .standard,
        secretStore: AIProviderSecretPersisting = AIProviderSecretStore()
    ) -> AnthropicSummaryConfig? {
        let rawBaseURL = defaults.stringOr(AppSettings.aiAnthropicBaseURL, default: defaultAnthropicBaseURL)
        let rawModel = defaults.stringOr(AppSettings.aiAnthropicModel, default: defaultAnthropicModel)
        let normalizedBaseURL = normalizeBaseURL(rawBaseURL)
        guard let baseURL = URL(string: normalizedBaseURL),
              !rawModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let apiKey = secretStore.apiKey(for: .anthropic),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return AnthropicSummaryConfig(
            baseURL: baseURL,
            model: rawModel.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey
        )
    }

    /// Ollama spricht den OpenAI-kompatiblen Endpoint, braucht aber keinen Key.
    /// Der Platzhalter-Key füllt nur den Bearer-Header, den Ollama ignoriert.
    static func ollamaConfig(defaults: UserDefaults = .standard) -> OpenAICompatibleSummaryConfig? {
        let rawBaseURL = defaults.stringOr(AppSettings.aiOllamaBaseURL, default: defaultOllamaBaseURL)
        let rawModel = defaults.stringOr(AppSettings.aiOllamaModel, default: defaultOllamaModel)
        let normalizedBaseURL = normalizeBaseURL(rawBaseURL)
        guard let baseURL = URL(string: normalizedBaseURL),
              !rawModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return OpenAICompatibleSummaryConfig(
            baseURL: baseURL,
            model: rawModel.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: "ollama"
        )
    }

    static func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    /// Baut den aktuell ausgewählten Provider inklusive Config. `nil` heißt:
    /// der gewählte Provider ist nicht einsatzbereit (z. B. fehlender API-Key).
    /// Der `PostProcessor` kennt nur dieses Ergebnis, nicht die einzelnen Anbieter.
    static func makeProvider(
        defaults: UserDefaults = .standard,
        secretStore: AIProviderSecretPersisting = AIProviderSecretStore()
    ) -> SummaryProvider? {
        switch selectedProvider(defaults: defaults) {
        case .claudeCLI:
            return ClaudeCLISummaryProvider()
        case .openAICompatible:
            guard let config = openAICompatibleConfig(defaults: defaults, secretStore: secretStore) else {
                return nil
            }
            return OpenAICompatibleSummaryProvider(config: config)
        case .anthropicAPI:
            guard let config = anthropicConfig(defaults: defaults, secretStore: secretStore) else {
                return nil
            }
            return AnthropicSummaryProvider(config: config)
        case .ollama:
            guard let config = ollamaConfig(defaults: defaults) else {
                return nil
            }
            return OpenAICompatibleSummaryProvider(config: config)
        }
    }
}
