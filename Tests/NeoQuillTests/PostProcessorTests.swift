import XCTest
@testable import NeoQuill

final class PostProcessorTests: XCTestCase {
    func testSkipsClaudeSummaryWhenAnalysisIsDisabled() async {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppSettings.claudeAnalysisEnabled)
        defaults.set(false, forKey: AppSettings.claudeAnalysisEnabled)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppSettings.claudeAnalysisEnabled)
            } else {
                defaults.removeObject(forKey: AppSettings.claudeAnalysisEnabled)
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
        let previousLocalOnly = defaults.object(forKey: AppSettings.localOnlyMode)
        let previousClaudeEnabled = defaults.object(forKey: AppSettings.claudeAnalysisEnabled)
        defaults.set(true, forKey: AppSettings.localOnlyMode)
        defaults.set(true, forKey: AppSettings.claudeAnalysisEnabled)
        defer {
            restore(previousLocalOnly, key: AppSettings.localOnlyMode)
            restore(previousClaudeEnabled, key: AppSettings.claudeAnalysisEnabled)
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
}
