import XCTest
@testable import NeoQuill

/// HTTP-Verhalten der beiden Netz-Provider über eine URLProtocol-gemockte
/// Session — Request-Form (Pfad, Auth-Header) und Antwort-Verarbeitung von
/// `summarize` und `probe` waren vorher komplett ungetestet, weil
/// `URLSession.shared` hartkodiert war.
final class SummaryProviderHTTPTests: XCTestCase {

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        session = nil
        super.tearDown()
    }

    private var openAIConfig: OpenAICompatibleSummaryConfig {
        OpenAICompatibleSummaryConfig(
            baseURL: URL(string: "https://api.example.com/v1")!,
            model: "test-model",
            apiKey: "sk-test"
        )
    }

    private var anthropicConfig: AnthropicSummaryConfig {
        AnthropicSummaryConfig(
            baseURL: URL(string: "https://api.anthropic.example/v1")!,
            model: "claude-test",
            apiKey: "sk-ant-test"
        )
    }

    private let summaryJSON = """
    {"title":"Sprint-Planung","tldr":"Kurzfassung.","highlights":[],"tasks":[],"chapters":[]}
    """

    // MARK: - OpenAI-kompatibel

    func testOpenAISummarizeParsesContentAndSendsBearerAuth() async {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            let payload = ["choices": [["message": ["content": self.summaryJSON]]]]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (MockURLProtocol.response(for: request, status: 200), data)
        }

        let provider = OpenAICompatibleSummaryProvider(config: openAIConfig, session: session)
        let summary = await provider.summarize(transcript: "ME [00:00]: Hallo", locale: "de")

        XCTAssertEqual(summary?.title, "Sprint-Planung")
        XCTAssertEqual(summary?.tldr, "Kurzfassung.")
    }

    func testOpenAISummarizeReturnsNilOnHTTPError() async {
        MockURLProtocol.handler = { request in
            (MockURLProtocol.response(for: request, status: 500), Data())
        }
        let provider = OpenAICompatibleSummaryProvider(config: openAIConfig, session: session)
        let summary = await provider.summarize(transcript: "ME [00:00]: Hallo", locale: "de")
        XCTAssertNil(summary)
    }

    func testOpenAIProbeReportsHTTPStatusOnFailure() async {
        MockURLProtocol.handler = { request in
            (MockURLProtocol.response(for: request, status: 401), Data("unauthorized".utf8))
        }
        let provider = OpenAICompatibleSummaryProvider(config: openAIConfig, session: session)
        let result = await provider.probe()
        guard case .failed(let reason) = result else {
            return XCTFail("Probe muss bei 401 fehlschlagen")
        }
        XCTAssertTrue(reason.contains("HTTP 401"), "Grund muss den Status nennen: \(reason)")
    }

    func testOpenAIProbeSucceedsAndNamesModel() async {
        MockURLProtocol.handler = { request in
            let payload = ["choices": [["message": ["content": "OK"]]]]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (MockURLProtocol.response(for: request, status: 200), data)
        }
        let provider = OpenAICompatibleSummaryProvider(config: openAIConfig, session: session)
        let result = await provider.probe()
        guard case .ok(let detail) = result else {
            return XCTFail("Probe muss bei 200 ok sein")
        }
        XCTAssertTrue(detail.contains("test-model"))
    }

    // MARK: - Anthropic

    func testAnthropicSummarizeParsesTextBlockAndSendsAPIKeyHeaders() async {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "anthropic-version"))
            let payload = ["content": [["type": "text", "text": self.summaryJSON]]]
            let data = try JSONSerialization.data(withJSONObject: payload)
            return (MockURLProtocol.response(for: request, status: 200), data)
        }

        let provider = AnthropicSummaryProvider(config: anthropicConfig, session: session)
        let summary = await provider.summarize(transcript: "ME [00:00]: Hallo", locale: "de")

        XCTAssertEqual(summary?.title, "Sprint-Planung")
    }

    func testAnthropicProbeReportsHTTPStatusOnFailure() async {
        MockURLProtocol.handler = { request in
            (MockURLProtocol.response(for: request, status: 403), Data("forbidden".utf8))
        }
        let provider = AnthropicSummaryProvider(config: anthropicConfig, session: session)
        let result = await provider.probe()
        guard case .failed(let reason) = result else {
            return XCTFail("Probe muss bei 403 fehlschlagen")
        }
        XCTAssertTrue(reason.contains("HTTP 403"))
    }
}

/// Minimaler URLProtocol-Mock — beantwortet jeden Request über den statischen
/// Handler. Alle Nutzer laufen in EINER Testklasse (XCTest seriell pro Klasse),
/// daher ist der geteilte Handler unkritisch.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
