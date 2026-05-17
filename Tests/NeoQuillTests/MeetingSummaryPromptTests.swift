import XCTest
@testable import NeoQuill

final class MeetingSummaryPromptTests: XCTestCase {
    func testAutoLocaleKeepsMixedLanguageInstruction() {
        let prompt = MeetingSummaryPrompt.build(
            transcript: "ME [00:00]: Hallo. S1 [00:05]: Let's ship.",
            locale: "auto"
        )

        XCTAssertTrue(prompt.contains("transcript mixes languages"))
    }

    func testParsesSummaryFromCodeFence() throws {
        let summary = try XCTUnwrap(MeetingSummaryPrompt.parseSummary("""
        ```json
        {
          "title": "Launch Planung",
          "tldr": "Wir planen den Launch.",
          "highlights": [{"label": "Entscheidung", "text": "Direct Sale zuerst.", "tone": "brand"}],
          "tasks": [{"who": "ME", "task": "Provider-Slice bauen", "due": "18. Mai", "status": "open"}],
          "chapters": [{"timestamp": "00:00", "label": "Launch", "duration": "3m"}]
        }
        ```
        """))

        XCTAssertEqual(summary.title, "Launch Planung")
        XCTAssertEqual(summary.highlights.first?.tone, "brand")
        XCTAssertEqual(summary.tasks.first?.who, "ME")
        XCTAssertEqual(summary.chapters.first?.label, "Launch")
    }
}
