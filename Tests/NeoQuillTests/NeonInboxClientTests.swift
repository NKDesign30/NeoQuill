import XCTest
@testable import NeoQuill

final class NeonInboxClientTests: XCTestCase {
    func testFreshDefaultsDoNotResolveLocalNeonEndpoint() throws {
        let defaults = try makeDefaults()

        XCTAssertNil(NeonInboxClient.resolvedEndpoint(defaults: defaults))
    }

    func testConfiguredEndpointIsResolved() throws {
        let defaults = try makeDefaults()
        defaults.set("https://automation.example.com/action-inbox/ingest", forKey: NeonInboxClient.endpointDefaultsKey)

        XCTAssertEqual(
            NeonInboxClient.resolvedEndpoint(defaults: defaults)?.absoluteString,
            "https://automation.example.com/action-inbox/ingest"
        )
    }

    func testMissingEndpointFailsBeforeNetwork() async throws {
        let defaults = try makeDefaults()
        let client = NeonInboxClient(endpoint: nil, defaults: defaults)
        let ingest = NeonInboxClient.Ingest(
            source: .neoquill,
            sourceId: "neoquill:meeting-1:action-1",
            title: "Follow-up",
            body: nil,
            priorityHint: nil,
            labels: []
        )

        do {
            _ = try await client.ingest(ingest)
            XCTFail("Expected missing endpoint error")
        } catch let error as NeonInboxClient.InboxError {
            XCTAssertEqual(error, .missingEndpoint)
            XCTAssertEqual(error.errorDescription, "Action-Inbox-Endpoint ist nicht konfiguriert.")
        }
    }

    func testInvalidEndpointIsRejected() throws {
        let defaults = try makeDefaults()
        defaults.set("not-a-url", forKey: NeonInboxClient.endpointDefaultsKey)

        XCTAssertNil(NeonInboxClient.resolvedEndpoint(defaults: defaults))
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "NeoQuillTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
