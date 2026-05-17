import Foundation
import Security

enum AISummaryProvider: String, CaseIterable, Codable, Identifiable {
    case claudeCLI = "claude_cli"
    case openAICompatible = "openai_compatible"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCLI:
            return "Claude CLI"
        case .openAICompatible:
            return "OpenAI-kompatibel"
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

protocol AIProviderSecretPersisting {
    func loadOpenAICompatibleAPIKey() -> String?
    func saveOpenAICompatibleAPIKey(_ apiKey: String) throws
    func clearOpenAICompatibleAPIKey()
}

final class AIProviderSecretStore: AIProviderSecretPersisting {
    private let service = "com.neon.quill.ai.openai-compatible"
    private let account = "api-key"

    func loadOpenAICompatibleAPIKey() -> String? {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
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

    func saveOpenAICompatibleAPIKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8) else { return }

        let baseQuery: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
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

    func clearOpenAICompatibleAPIKey() {
        let query: [CFString: CFTypeRef] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service as CFString,
            kSecAttrAccount: account as CFString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AIProviderSettings {
    static let defaultProvider = AISummaryProvider.claudeCLI.rawValue
    static let defaultOpenAIBaseURL = "https://api.openai.com/v1"
    static let defaultOpenAIModel = "gpt-5.1"

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
              let apiKey = secretStore.loadOpenAICompatibleAPIKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return OpenAICompatibleSummaryConfig(
            baseURL: baseURL,
            model: rawModel.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey
        )
    }

    static func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }
}
