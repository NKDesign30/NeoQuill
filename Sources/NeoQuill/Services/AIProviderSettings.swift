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
        // Unbekannter rawValue fällt auf denselben Default wie "nicht gesetzt" —
        // vorher zwei verschiedene Fallbacks (.openAICompatible vs .claudeCLI)
        // für zwei Spielarten von "nicht gesetzt".
        return AISummaryProvider(rawValue: raw) ?? .openAICompatible
    }

    static func openAICompatibleConfig(
        defaults: UserDefaults = .standard,
        secretStore: AIProviderSecretPersisting = AIProviderSecretStore()
    ) -> OpenAICompatibleSummaryConfig? {
        try? openAICompatibleConfigResult(defaults: defaults, secretStore: secretStore).get()
    }

    static func anthropicConfig(
        defaults: UserDefaults = .standard,
        secretStore: AIProviderSecretPersisting = AIProviderSecretStore()
    ) -> AnthropicSummaryConfig? {
        try? anthropicConfigResult(defaults: defaults, secretStore: secretStore).get()
    }

    /// Ollama spricht den OpenAI-kompatiblen Endpoint, braucht aber keinen Key.
    /// Der Platzhalter-Key füllt nur den Bearer-Header, den Ollama ignoriert.
    static func ollamaConfig(defaults: UserDefaults = .standard) -> OpenAICompatibleSummaryConfig? {
        try? ollamaConfigResult(defaults: defaults).get()
    }

    static func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    // MARK: - Result-Varianten (Fehlergrund statt stummem nil)

    private static func openAICompatibleConfigResult(
        defaults: UserDefaults,
        secretStore: AIProviderSecretPersisting
    ) -> Result<OpenAICompatibleSummaryConfig, ProviderConfigError> {
        openAIStyleConfig(
            provider: .openAICompatible,
            rawBaseURL: defaults.stringOr(AppSettings.aiSummaryBaseURL, default: defaultOpenAIBaseURL),
            rawModel: defaults.stringOr(AppSettings.aiSummaryModel, default: defaultOpenAIModel),
            apiKey: secretStore.apiKey(for: .openAICompatible)
        )
    }

    private static func ollamaConfigResult(
        defaults: UserDefaults
    ) -> Result<OpenAICompatibleSummaryConfig, ProviderConfigError> {
        openAIStyleConfig(
            provider: .ollama,
            rawBaseURL: defaults.stringOr(AppSettings.aiOllamaBaseURL, default: defaultOllamaBaseURL),
            rawModel: defaults.stringOr(AppSettings.aiOllamaModel, default: defaultOllamaModel),
            apiKey: "ollama"
        )
    }

    private static func anthropicConfigResult(
        defaults: UserDefaults,
        secretStore: AIProviderSecretPersisting
    ) -> Result<AnthropicSummaryConfig, ProviderConfigError> {
        let rawBaseURL = defaults.stringOr(AppSettings.aiAnthropicBaseURL, default: defaultAnthropicBaseURL)
        let rawModel = defaults.stringOr(AppSettings.aiAnthropicModel, default: defaultAnthropicModel)
        guard let baseURL = URL(string: normalizeBaseURL(rawBaseURL)) else {
            return .failure(.invalidBaseURL(.anthropicAPI))
        }
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return .failure(.missingModel(.anthropicAPI)) }
        guard let apiKey = secretStore.apiKey(for: .anthropic),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingAPIKey(.anthropicAPI))
        }
        return .success(AnthropicSummaryConfig(baseURL: baseURL, model: model, apiKey: apiKey))
    }

    private static func openAIStyleConfig(
        provider: AISummaryProvider,
        rawBaseURL: String,
        rawModel: String,
        apiKey: String?
    ) -> Result<OpenAICompatibleSummaryConfig, ProviderConfigError> {
        guard let baseURL = URL(string: normalizeBaseURL(rawBaseURL)) else {
            return .failure(.invalidBaseURL(provider))
        }
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return .failure(.missingModel(provider)) }
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingAPIKey(provider))
        }
        return .success(OpenAICompatibleSummaryConfig(baseURL: baseURL, model: model, apiKey: apiKey))
    }

    // MARK: - Provider-Factory

    /// Baut den aktuell ausgewählten Provider inklusive Config — oder den
    /// konkreten Grund, warum nicht. Die Probe-UI zeigt damit "API-Key fehlt"
    /// statt eines generischen "ging nicht"; vorher kollabierten kaputte URL,
    /// fehlendes Modell und fehlender Key zu einem stummen `nil`, eine Ebene
    /// bevor `ProviderProbeResult` überhaupt greifen konnte.
    static func makeProviderResult(
        defaults: UserDefaults = .standard,
        secretStore: AIProviderSecretPersisting = AIProviderSecretStore(),
        session: URLSession = .shared
    ) -> Result<SummaryProvider, ProviderConfigError> {
        switch selectedProvider(defaults: defaults) {
        case .claudeCLI:
            return .success(ClaudeCLISummaryProvider())
        case .openAICompatible:
            return openAICompatibleConfigResult(defaults: defaults, secretStore: secretStore)
                .map { OpenAICompatibleSummaryProvider(config: $0, session: session) as SummaryProvider }
        case .anthropicAPI:
            return anthropicConfigResult(defaults: defaults, secretStore: secretStore)
                .map { AnthropicSummaryProvider(config: $0, session: session) as SummaryProvider }
        case .ollama:
            return ollamaConfigResult(defaults: defaults)
                .map { OpenAICompatibleSummaryProvider(config: $0, session: session) as SummaryProvider }
        }
    }

    /// Bequeme nil-Variante für Caller, die den Fehlergrund nicht brauchen.
    static func makeProvider(
        defaults: UserDefaults = .standard,
        secretStore: AIProviderSecretPersisting = AIProviderSecretStore(),
        session: URLSession = .shared
    ) -> SummaryProvider? {
        try? makeProviderResult(defaults: defaults, secretStore: secretStore, session: session).get()
    }
}

/// Warum kein Provider gebaut werden konnte. Trägt den Provider mit, damit
/// die Meldung benennt, WESSEN Config unvollständig ist.
enum ProviderConfigError: Error, Equatable {
    case invalidBaseURL(AISummaryProvider)
    case missingModel(AISummaryProvider)
    case missingAPIKey(AISummaryProvider)

    var userMessage: String {
        switch self {
        case .invalidBaseURL(let provider):
            return "\(provider.displayName): Endpoint-URL ist ungültig."
        case .missingModel(let provider):
            return "\(provider.displayName): Kein Modell angegeben."
        case .missingAPIKey(let provider):
            return "\(provider.displayName): API-Key fehlt — in den Einstellungen hinterlegen."
        }
    }
}
