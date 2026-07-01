import XCTest
@testable import NeoQuill

final class AIProviderSettingsTests: XCTestCase {
    func testBuildsOpenAICompatibleConfigFromDefaultsAndSecret() throws {
        let defaults = try makeDefaults()
        let store = InMemoryAIProviderSecretStore()
        defaults.set("https://api.openai.com/v1/", forKey: AppSettings.aiSummaryBaseURL.key)
        defaults.set("gpt-5.1", forKey: AppSettings.aiSummaryModel.key)
        try store.setAPIKey("sk-test", for: .openAICompatible)

        let config = try XCTUnwrap(
            AIProviderSettings.openAICompatibleConfig(defaults: defaults, secretStore: store)
        )

        XCTAssertEqual(config.baseURL.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(config.chatCompletionsURL.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(config.model, "gpt-5.1")
        XCTAssertEqual(config.apiKey, "sk-test")
    }

    func testOpenAICompatibleConfigRequiresSecret() throws {
        let defaults = try makeDefaults()
        defaults.set("https://api.openai.com/v1", forKey: AppSettings.aiSummaryBaseURL.key)
        defaults.set("gpt-5.1", forKey: AppSettings.aiSummaryModel.key)

        XCTAssertNil(
            AIProviderSettings.openAICompatibleConfig(defaults: defaults, secretStore: InMemoryAIProviderSecretStore())
        )
    }

    func testBuildsAnthropicConfigFromDefaultsAndSecret() throws {
        let defaults = try makeDefaults()
        let store = InMemoryAIProviderSecretStore()
        defaults.set("https://api.anthropic.com/v1/", forKey: AppSettings.aiAnthropicBaseURL.key)
        defaults.set("claude-haiku-4-5", forKey: AppSettings.aiAnthropicModel.key)
        try store.setAPIKey("sk-ant-test", for: .anthropic)

        let config = try XCTUnwrap(
            AIProviderSettings.anthropicConfig(defaults: defaults, secretStore: store)
        )

        XCTAssertEqual(config.baseURL.absoluteString, "https://api.anthropic.com/v1")
        XCTAssertEqual(config.messagesURL.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(config.model, "claude-haiku-4-5")
        XCTAssertEqual(config.apiKey, "sk-ant-test")
    }

    func testAnthropicConfigRequiresSecret() throws {
        let defaults = try makeDefaults()
        defaults.set("claude-haiku-4-5", forKey: AppSettings.aiAnthropicModel.key)

        XCTAssertNil(
            AIProviderSettings.anthropicConfig(defaults: defaults, secretStore: InMemoryAIProviderSecretStore())
        )
    }

    func testBuildsOllamaConfigWithoutAPIKey() throws {
        let defaults = try makeDefaults()
        defaults.set("http://localhost:11434/v1/", forKey: AppSettings.aiOllamaBaseURL.key)
        defaults.set("llama3.1", forKey: AppSettings.aiOllamaModel.key)

        let config = try XCTUnwrap(AIProviderSettings.ollamaConfig(defaults: defaults))

        XCTAssertEqual(config.baseURL.absoluteString, "http://localhost:11434/v1")
        XCTAssertEqual(config.chatCompletionsURL.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(config.model, "llama3.1")
        XCTAssertFalse(config.apiKey.isEmpty)
    }

    func testOllamaProviderDoesNotRequireAPIKey() {
        XCTAssertFalse(AISummaryProvider.ollama.requiresAPIKey)
        XCTAssertTrue(AISummaryProvider.anthropicAPI.requiresAPIKey)
        XCTAssertTrue(AISummaryProvider.openAICompatible.requiresAPIKey)
        XCTAssertFalse(AISummaryProvider.claudeCLI.requiresAPIKey)
    }

    func testOpenAIAndAnthropicKeysAreIsolatedByScope() throws {
        let store = InMemoryAIProviderSecretStore()
        try store.setAPIKey("sk-openai", for: .openAICompatible)
        try store.setAPIKey("sk-ant", for: .anthropic)

        XCTAssertEqual(store.apiKey(for: .openAICompatible), "sk-openai")
        XCTAssertEqual(store.apiKey(for: .anthropic), "sk-ant")

        store.clearAPIKey(for: .openAICompatible)
        XCTAssertNil(store.apiKey(for: .openAICompatible))
        XCTAssertEqual(store.apiKey(for: .anthropic), "sk-ant")
    }

    func testMakeProviderReturnsClaudeCLIWithoutConfig() throws {
        let defaults = try makeDefaults()
        defaults.set(AISummaryProvider.claudeCLI.rawValue, forKey: AppSettings.aiSummaryProvider.key)
        let provider = AIProviderSettings.makeProvider(defaults: defaults, secretStore: InMemoryAIProviderSecretStore())
        XCTAssertTrue(provider is ClaudeCLISummaryProvider)
    }

    func testMakeProviderReturnsNilForOpenAIWithoutKey() throws {
        let defaults = try makeDefaults()
        defaults.set(AISummaryProvider.openAICompatible.rawValue, forKey: AppSettings.aiSummaryProvider.key)
        defaults.set("https://api.openai.com/v1", forKey: AppSettings.aiSummaryBaseURL.key)
        defaults.set("gpt-5.1", forKey: AppSettings.aiSummaryModel.key)
        let provider = AIProviderSettings.makeProvider(defaults: defaults, secretStore: InMemoryAIProviderSecretStore())
        XCTAssertNil(provider)
    }

    func testMakeProviderReturnsOllamaWithoutKey() throws {
        let defaults = try makeDefaults()
        defaults.set(AISummaryProvider.ollama.rawValue, forKey: AppSettings.aiSummaryProvider.key)
        defaults.set("http://localhost:11434/v1", forKey: AppSettings.aiOllamaBaseURL.key)
        defaults.set("llama3.1", forKey: AppSettings.aiOllamaModel.key)
        let provider = AIProviderSettings.makeProvider(defaults: defaults, secretStore: InMemoryAIProviderSecretStore())
        XCTAssertTrue(provider is OpenAICompatibleSummaryProvider)
    }

    func testMakeProviderReturnsAnthropicWithKey() throws {
        let defaults = try makeDefaults()
        defaults.set(AISummaryProvider.anthropicAPI.rawValue, forKey: AppSettings.aiSummaryProvider.key)
        let store = InMemoryAIProviderSecretStore()
        try store.setAPIKey("sk-ant", for: .anthropic)
        let provider = AIProviderSettings.makeProvider(defaults: defaults, secretStore: store)
        XCTAssertTrue(provider is AnthropicSummaryProvider)
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "NeoQuillTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private final class InMemoryAIProviderSecretStore: AIProviderSecretPersisting {
    private var keys: [AIProviderKeyScope: String] = [:]

    func apiKey(for scope: AIProviderKeyScope) -> String? {
        keys[scope]
    }

    func setAPIKey(_ apiKey: String, for scope: AIProviderKeyScope) throws {
        keys[scope] = apiKey
    }

    func clearAPIKey(for scope: AIProviderKeyScope) {
        keys[scope] = nil
    }
}
