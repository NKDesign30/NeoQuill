import XCTest
@testable import NeoQuill

final class PostProcessorTests: XCTestCase {
    func testSkipsClaudeSummaryWhenAnalysisIsDisabled() async {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppSettings.claudeAnalysisEnabled.key)
        defaults.set(false, forKey: AppSettings.claudeAnalysisEnabled.key)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppSettings.claudeAnalysisEnabled.key)
            } else {
                defaults.removeObject(forKey: AppSettings.claudeAnalysisEnabled.key)
            }
        }

        let body = "Wir entscheiden den Launch nach dem Provider-Slice."
        let line = TranscriptLine(who: "ME", timestamp: "00:00", body: body)

        let result = await PostProcessor.process(
            meetingId: "test-\(UUID().uuidString)",
            transcriptLines: [line],
            locale: "de"
        )

        XCTAssertEqual(result.title, body)
        XCTAssertEqual(result.tldr, body)
        XCTAssertTrue(result.highlights.isEmpty)
        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertTrue(result.chapters.isEmpty)
    }

    func testSkipsProviderSummaryInLocalOnlyMode() async {
        let defaults = UserDefaults.standard
        let previousLocalOnly = defaults.object(forKey: AppSettings.localOnlyMode.key)
        let previousClaudeEnabled = defaults.object(forKey: AppSettings.claudeAnalysisEnabled.key)
        defaults.set(true, forKey: AppSettings.localOnlyMode.key)
        defaults.set(true, forKey: AppSettings.claudeAnalysisEnabled.key)
        defer {
            restore(previousLocalOnly, key: AppSettings.localOnlyMode.key)
            restore(previousClaudeEnabled, key: AppSettings.claudeAnalysisEnabled.key)
        }

        let body = "Bitte Follow-up Meeting erstellen."
        let line = TranscriptLine(who: "ME", timestamp: "00:00", body: body)

        let result = await PostProcessor.process(
            meetingId: "test-\(UUID().uuidString)",
            transcriptLines: [line],
            locale: "de"
        )

        XCTAssertEqual(result.title, body)
        XCTAssertEqual(result.tldr, body)
        XCTAssertTrue(result.highlights.isEmpty)
        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertTrue(result.chapters.isEmpty)
    }

    private func restore(_ value: Any?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Happy Path (injizierter Provider + injizierte Defaults)

    /// Der Erfolgs-Pfad war vorher untestbar: Provider-Factory und Defaults
    /// waren hartverdrahtet, Tests konnten nur Skip-Pfade über Mutation von
    /// `UserDefaults.standard` erreichen.
    func testUsesProviderSummaryWhenGateIsOpen() async {
        let summary = MeetingSummaryAI(
            title: "Sprint-Planung",
            tldr: "Wir planen den Launch.",
            highlights: [HighlightAI(label: "Entscheidung", text: "Launch am Freitag", tone: "brand")],
            tasks: [TaskAI(who: "Alex", task: "Release bauen", due: "Fr", status: "open")],
            chapters: [ChapterAI(timestamp: "00:00", label: "Planung", duration: "5m")]
        )
        let line = TranscriptLine(who: "ME", timestamp: "00:00", body: "Wir planen den Launch.")

        let result = await PostProcessor.process(
            meetingId: "test-\(UUID().uuidString)",
            transcriptLines: [line],
            locale: "de",
            defaults: makeCleanDefaults(),
            providerFactory: { TestSummaryProvider(result: summary) }
        )

        XCTAssertEqual(result.title, "Sprint-Planung")
        XCTAssertEqual(result.tldr, "Wir planen den Launch.")
        XCTAssertEqual(result.highlights.count, 1)
        XCTAssertEqual(result.tasks.count, 1)
        XCTAssertEqual(result.chapters.count, 1)
    }

    func testPassesWorkspaceContextToProviderPromptInput() async {
        let line = TranscriptLine(who: "ME", timestamp: "00:00", body: "Wir prüfen die Roadmap.")

        let result = await PostProcessor.process(
            meetingId: "test-\(UUID().uuidString)",
            transcriptLines: [line],
            locale: "de",
            context: "Name: DAT\nArt: Organisation\nNotiz: Fokus auf Händlerprozesse.",
            defaults: makeCleanDefaults(),
            providerFactory: {
                WorkspaceContextSummaryProvider(
                    expectedContext: "Name: DAT",
                    expectedTranscript: "Wir prüfen die Roadmap."
                )
            }
        )

        XCTAssertEqual(result.title, "Workspace-Kontext erkannt")
    }

    func testGateClosedSkipsProviderEvenWhenFactoryWouldSucceed() async {
        let defaults = makeCleanDefaults()
        defaults.set(true, forKey: AppSettings.localOnlyMode.key)
        let body = "Lokal bleiben."
        let line = TranscriptLine(who: "ME", timestamp: "00:00", body: body)

        let result = await PostProcessor.process(
            meetingId: "test-\(UUID().uuidString)",
            transcriptLines: [line],
            locale: "de",
            defaults: defaults,
            providerFactory: {
                XCTFail("Bei geschlossenem Gate darf die Factory nie gefragt werden")
                return nil
            }
        )

        XCTAssertEqual(result.title, body)
        XCTAssertTrue(result.highlights.isEmpty)
    }

    private func makeCleanDefaults() -> UserDefaults {
        let name = "NeoQuillTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

private struct TestSummaryProvider: SummaryProvider {
    let result: MeetingSummaryAI?
    func summarize(transcript: String, locale: String) async -> MeetingSummaryAI? { result }
    func probe() async -> ProviderProbeResult { .ok("ok") }
}

private struct WorkspaceContextSummaryProvider: SummaryProvider {
    let expectedContext: String
    let expectedTranscript: String

    func summarize(transcript: String, locale: String) async -> MeetingSummaryAI? {
        let title = transcript.contains(expectedContext) && transcript.contains(expectedTranscript)
            ? "Workspace-Kontext erkannt"
            : "Workspace-Kontext fehlt"
        return MeetingSummaryAI(title: title, tldr: "", highlights: [], tasks: [], chapters: [])
    }

    func probe() async -> ProviderProbeResult { .ok("ok") }
}
