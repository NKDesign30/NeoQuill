import XCTest
@testable import NeoQuill

final class MeetingActionGeneratorTests: XCTestCase {
    func testSuggestsReviewableActionsFromMeetingOutput() {
        let meeting = makeMeeting(
            tasks: [
                ActionItem(id: "task-1", who: "ME", task: "Frontend Bug fixen", due: "20. Mai", status: .open),
                ActionItem(id: "task-2", who: "S1", task: "Kundenfreigabe einholen", due: "21. Mai", status: .open),
            ],
            highlights: [
                Highlight(label: "Risiko", text: "Launch hängt an Freigabe.", tone: .warning),
            ]
        )

        let actions = MeetingActionGenerator.suggest(for: meeting)
        let kinds = actions.map(\.kind)

        XCTAssertTrue(kinds.contains(.followUpEmail))
        XCTAssertTrue(kinds.contains(.followUpMeeting))
        XCTAssertTrue(kinds.contains(.jiraTicket))
        XCTAssertTrue(kinds.contains(.inboxTask))
        XCTAssertTrue(kinds.contains(.webhookPayload))
    }

    func testSkipsActionsWhileMeetingIsProcessing() {
        let actions = MeetingActionGenerator.suggest(for: makeMeeting(lifecycle: .transcribing))

        XCTAssertTrue(actions.isEmpty)
    }

    private func makeMeeting(
        tasks: [ActionItem] = [],
        highlights: [Highlight] = [],
        lifecycle: MeetingLifecycle = .done
    ) -> MeetingDetail {
        MeetingDetail(
            id: "meeting-1",
            title: "Launch Planung",
            dateLong: "Sonntag, 17. Mai",
            timeRange: "10:00 – 10:30",
            duration: "30m",
            platform: .meet,
            wordCount: 420,
            participants: [
                Participant(id: "ME", name: "Niko", role: "Owner", colorHex: 0x2ECC71, spoke: "12m"),
                Participant(id: "S1", name: "Sarah", role: "Kunde", colorHex: 0x3498DB, spoke: "18m"),
            ],
            tldr: "Wir planen Launch und offene Punkte.",
            highlights: highlights,
            tasks: tasks,
            chapters: [],
            transcript: [
                TranscriptLine(who: "ME", timestamp: "00:00", body: "Wir planen Launch und offene Punkte."),
            ],
            audioURL: nil,
            lifecycle: lifecycle
        )
    }
}
