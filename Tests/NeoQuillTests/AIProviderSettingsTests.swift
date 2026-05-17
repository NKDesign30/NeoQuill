import XCTest
@testable import NeoQuill

final class AIProviderSettingsTests: XCTestCase {
    func testBuildsOpenAICompatibleConfigFromDefaultsAndSecret() throws {
        let defaults = try makeDefaults()
        let store = InMemoryAIProviderSecretStore()
        defaults.set("https://api.openai.com/v1/", forKey: AppSettings.aiSummaryBaseURL)
        defaults.set("gpt-5.1", forKey: AppSettings.aiSummaryModel)
        try store.saveOpenAICompatibleAPIKey("sk-test")

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
        defaults.set("https://api.openai.com/v1", forKey: AppSettings.aiSummaryBaseURL)
        defaults.set("gpt-5.1", forKey: AppSettings.aiSummaryModel)

        XCTAssertNil(
            AIProviderSettings.openAICompatibleConfig(defaults: defaults, secretStore: InMemoryAIProviderSecretStore())
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "NeoQuillTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private final class InMemoryAIProviderSecretStore: AIProviderSecretPersisting {
    private var apiKey: String?

    func loadOpenAICompatibleAPIKey() -> String? {
        apiKey
    }

    func saveOpenAICompatibleAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }

    func clearOpenAICompatibleAPIKey() {
        apiKey = nil
    }
}
