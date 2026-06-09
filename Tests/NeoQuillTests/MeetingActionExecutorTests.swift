import XCTest
@testable import NeoQuill

final class MeetingActionExecutorTests: XCTestCase {
    func testMailtoURLContainsSubjectAndBody() throws {
        let meeting = makeMeeting()
        let action = makeAction(kind: .followUpEmail, body: "Danke für das Gespräch.")

        let url = try XCTUnwrap(MeetingActionExecutor.mailtoURL(for: action, meeting: meeting))
        let absolute = url.absoluteString

        XCTAssertTrue(absolute.hasPrefix("mailto:"))
        XCTAssertTrue(absolute.contains("Follow-up"))
        XCTAssertTrue(absolute.contains("Danke"))
    }

    func testCalendarInviteContentIsValidVEventShape() {
        let content = MeetingActionExecutor.calendarInviteContent(
            for: makeAction(kind: .followUpMeeting),
            meeting: makeMeeting(),
            now: Date(timeIntervalSince1970: 1_779_000_000)
        )

        XCTAssertTrue(content.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(content.contains("BEGIN:VEVENT"))
        XCTAssertTrue(content.contains("SUMMARY:Follow-up planen"))
        XCTAssertTrue(content.contains("DESCRIPTION:Agenda"))
    }

    func testJiraDraftContainsMeetingContext() {
        let draft = MeetingActionExecutor.jiraDraft(
            for: makeAction(kind: .jiraTicket, body: "Login Bug fixen"),
            meeting: makeMeeting()
        )

        XCTAssertTrue(draft.contains("Summary: Login Bug fixen"))
        XCTAssertTrue(draft.contains("Meeting: Launch Planung"))
        XCTAssertTrue(draft.contains("Acceptance:"))
    }

    func testWebhookPayloadContainsActionAndMeeting() throws {
        let payload = try MeetingActionExecutor.webhookPayload(
            for: makeAction(kind: .webhookPayload, body: "Automation starten"),
            meeting: makeMeeting()
        )

        XCTAssertTrue(payload.contains("\"meetingId\" : \"meeting-1\""))
        XCTAssertTrue(payload.contains("\"kind\" : \"webhookPayload\""))
        XCTAssertTrue(payload.contains("\"body\" : \"Automation starten\""))
    }

    private func makeAction(kind: MeetingActionKind, body: String = "Agenda vorbereiten") -> MeetingAction {
        MeetingAction(
            id: "action-1",
            kind: kind,
            title: kind == .followUpMeeting ? "Follow-up planen" : "Aktion vorbereiten",
            summary: "Test summary",
            body: body,
            assignee: "ME",
            due: "20. Mai",
            source: "Test source",
            confidence: 0.8
        )
    }

    private func makeMeeting() -> MeetingDetail {
        MeetingDetail(
            id: "meeting-1",
            title: "Launch Planung",
            dateLong: "Sonntag, 17. Mai",
            timeRange: "10:00 – 10:30",
            duration: "30m",
            platform: .meet,
            wordCount: 420,
            participants: [],
            tldr: "Wir planen den Launch.",
            highlights: [],
            tasks: [],
            chapters: [],
            transcript: [],
            audioURL: nil,
            lifecycle: .done
        )
    }
}
