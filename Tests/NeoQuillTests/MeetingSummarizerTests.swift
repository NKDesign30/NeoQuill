import XCTest
@testable import NeoQuill

final class MeetingSummarizerTests: XCTestCase {

    func testTaskIdsUseMeetingIdAndPrefix() {
        let tasks = [taskAI(who: "Niko"), taskAI(who: "Babsi")]
        let mapped = MeetingSummarizer.mapTasks(tasks, meetingId: "m42", idPrefix: "merge-")
        XCTAssertEqual(mapped.map(\.id), ["m42-merge-task-0", "m42-merge-task-1"])
    }

    func testEmptyPrefixKeepsPlainTaskIds() {
        let mapped = MeetingSummarizer.mapTasks([taskAI(who: "Niko")], meetingId: "m1", idPrefix: "")
        XCTAssertEqual(mapped.first?.id, "m1-task-0")
    }

    func testEmptyWhoFallsBackToPlaceholder() {
        let mapped = MeetingSummarizer.mapTasks([taskAI(who: "")], meetingId: "m1", idPrefix: "")
        XCTAssertEqual(mapped.first?.who, "??")
    }

    func testTaskStatusMapsDoneAndOpen() {
        let mapped = MeetingSummarizer.mapTasks(
            [taskAI(who: "a", status: "done"), taskAI(who: "b", status: "open")],
            meetingId: "m1", idPrefix: ""
        )
        XCTAssertEqual(mapped[0].status, .done)
        XCTAssertEqual(mapped[1].status, .open)
    }

    func testChapterIdsUseMeetingIdAndPrefix() {
        let chapters = [ChapterAI(timestamp: "00:00", label: "Intro", duration: "2m")]
        let mapped = MeetingSummarizer.mapChapters(chapters, meetingId: "m7", idPrefix: "reprocess-")
        XCTAssertEqual(mapped.first?.id, "m7-reprocess-ch-0")
        XCTAssertEqual(mapped.first?.label, "Intro")
    }

    func testHighlightToneMapping() {
        XCTAssertEqual(MeetingSummarizer.mapHighlight(highlightAI(tone: "warning")).tone, .warning)
        XCTAssertEqual(MeetingSummarizer.mapHighlight(highlightAI(tone: "INFO")).tone, .info)
        XCTAssertEqual(MeetingSummarizer.mapHighlight(highlightAI(tone: "anything")).tone, .brand)
    }

    private func taskAI(who: String, status: String = "open") -> TaskAI {
        TaskAI(who: who, task: "etwas tun", due: "morgen", status: status)
    }

    private func highlightAI(tone: String) -> HighlightAI {
        HighlightAI(label: "Entscheidung", text: "Text", tone: tone)
    }
}
