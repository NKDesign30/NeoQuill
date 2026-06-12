import XCTest
@testable import NeoQuill

final class MeetingInboxBridgeTests: XCTestCase {
    func testMeetingActionIngestLabelsJiraSkillBridge() {
        let action = MeetingAction(
            id: "action-jira-1",
            kind: .jiraTicket,
            title: "Jira Ticket: Login Bug fixen",
            summary: "Ticket-Draft mit Meeting-Kontext.",
            body: "Login Bug fixen",
            assignee: "ME",
            due: "20. Mai",
            source: "Login bricht im Checkout ab.",
            confidence: 0.82
        )

        let ingest = MeetingInboxBridge.ingest(for: action, from: makeMeeting())

        XCTAssertEqual(ingest.source, .neoquill)
        XCTAssertTrue(ingest.sourceId.contains("meeting-1"))
        XCTAssertTrue(ingest.labels.contains("skill:jira"))
        XCTAssertEqual(ingest.priorityHint, .high)
        XCTAssertTrue(ingest.body?.contains("Jira-Ticket") == true)
        XCTAssertTrue(ingest.body?.contains("Login Bug fixen") == true)
    }

    func testMeetingActionIngestLabelsGogForCalendarAction() {
        let action = MeetingAction(
            id: "action-calendar-1",
            kind: .followUpMeeting,
            title: "Follow-up Meeting planen",
            summary: "30-Minuten-Termin.",
            body: "Agenda",
            assignee: "ME",
            due: "Nächster Werktag",
            source: "Meeting",
            confidence: 0.78
        )

        let ingest = MeetingInboxBridge.ingest(for: action, from: makeMeeting())

        XCTAssertTrue(ingest.labels.contains("skill:gog"))
        XCTAssertTrue(ingest.labels.contains("calendar"))
        XCTAssertEqual(ingest.priorityHint, .medium)
        XCTAssertTrue(ingest.body?.contains("Kalender-Event über gog") == true)
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
            participants: [
                Participant(id: "ME", name: "Alex", role: "Owner", colorHex: 0x2EAB73, spoke: "10m")
            ],
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
