import XCTest
@testable import NeoQuill

final class MeetingStoreRelabelTests: XCTestCase {
    private var tempDirectory: URL!
    private var store: MeetingStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingStoreRelabelTests-\(UUID().uuidString)", isDirectory: true)
        store = MeetingStore(url: tempDirectory.appendingPathComponent("meetings.sqlite"))
    }

    override func tearDown() {
        store = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    @MainActor
    func testRelabelSpeakerUpdatesGeneratedNotesAndTranscript() {
        let meetingId = "meeting-1"
        store.insert(
            summary: MeetingSummary(
                id: meetingId,
                title: "Weekly",
                date: "24. Mai",
                time: "12:00",
                duration: "12m",
                platform: .zoom,
                wordCount: 42,
                group: "Heute",
                participantIds: ["S1"],
                unread: true
            ),
            detail: MeetingDetail(
                id: meetingId,
                title: "Weekly",
                dateLong: "Sonntag, 24. Mai",
                timeRange: "12:00 - 12:12",
                duration: "12m",
                platform: .zoom,
                wordCount: 42,
                participants: [
                    Participant(id: "S1", name: "Speaker S1", role: "Erkannt", colorHex: 0x7C8AFF, spoke: "4m")
                ],
                tldr: "Speaker S1 bestätigt Budget. S1 liefert Angebot. Speaker 1 bleibt nicht stehen.",
                highlights: [
                    Highlight(label: "Speaker S1 Entscheidung", text: "S1 übernimmt den nächsten Schritt.", tone: .brand)
                ],
                tasks: [
                    ActionItem(id: "task-1", who: "S1", task: "Speaker S1 sendet die Unterlagen.", due: "morgen", status: .open)
                ],
                chapters: [
                    Chapter(id: "chapter-1", timestamp: "00:30", label: "Speaker 1 klärt Budget", duration: "2m")
                ],
                transcript: [
                    TranscriptLine(who: "S1", displayName: "Speaker S1", timestamp: "00:14", body: "Budget passt.")
                ]
            )
        )
        _ = waitForPublishedDetail(meetingId)

        store.relabelSpeaker(meetingId: meetingId, from: "S1", to: "speaker-alex", name: "Alex", colorHex: 0x2EAB73)

        let updated = waitForPublishedDetail(meetingId)
        XCTAssertEqual(updated?.participants.first?.id, "speaker-alex")
        XCTAssertEqual(updated?.participants.first?.name, "Alex")
        XCTAssertEqual(updated?.tldr, "Alex bestätigt Budget. Alex liefert Angebot. Alex bleibt nicht stehen.")
        XCTAssertEqual(updated?.highlights.first?.label, "Alex Entscheidung")
        XCTAssertEqual(updated?.highlights.first?.text, "Alex übernimmt den nächsten Schritt.")
        XCTAssertEqual(updated?.tasks.first?.who, "speaker-alex")
        XCTAssertEqual(updated?.tasks.first?.task, "Alex sendet die Unterlagen.")
        XCTAssertEqual(updated?.chapters.first?.label, "Alex klärt Budget")
        XCTAssertEqual(updated?.transcript.first?.who, "speaker-alex")
        XCTAssertEqual(updated?.transcript.first?.displayName, "Alex")
        XCTAssertEqual(updated?.transcript.first?.body, "Budget passt.")
    }

    @MainActor
    private func waitForPublishedDetail(_ meetingId: String) -> MeetingDetail? {
        store.detail(for: meetingId)
    }
}
