import XCTest
@testable import NeoQuill

/// Pinnt das Kern-Schreibverhalten des MeetingStore fest — bisher war von den
/// Writes nur `relabelSpeaker` getestet. Insbesondere: Sidebar- und
/// Detail-Titel sind EINE Spalte und kommen aus `detail.title`.
final class MeetingStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: MeetingStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoQuillTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
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

    private func makeMeeting(
        id: String,
        title: String,
        lifecycle: MeetingLifecycle = .done,
        workspaceId: String? = nil
    ) -> (MeetingSummary, MeetingDetail) {
        let summary = MeetingSummary(
            id: id, title: title, date: "10.06.", time: "09:00",
            duration: "12m", platform: .teams, wordCount: 0,
            group: "Diesen Monat", participantIds: [], unread: false,
            workspaceId: workspaceId
        )
        let detail = MeetingDetail(
            id: id, title: title, dateLong: "10. Juni 2026", timeRange: "09:00–09:12",
            duration: "12m", platform: .teams, wordCount: 0,
            participants: [], tldr: "—",
            highlights: [], tasks: [], chapters: [],
            transcript: [], audioURL: nil, lifecycle: lifecycle,
            workspaceId: workspaceId
        )
        return (summary, detail)
    }

    // MARK: - Insert/Update Round-Trip

    func testInsertThenReadBackRoundTrip() {
        let (summary, detail) = makeMeeting(id: "rec-001", title: "Sprint-Planung")
        store.insert(summary: summary, detail: detail)

        XCTAssertEqual(store.meetings.first?.id, "rec-001")
        XCTAssertEqual(store.meetings.first?.title, "Sprint-Planung")
        XCTAssertEqual(store.detail(for: "rec-001")?.title, "Sprint-Planung")
        XCTAssertEqual(store.detail(for: "rec-001")?.lifecycle, .done)
    }

    /// Die frühere `summaryTitle:`-Doppelung ist weg: der Sidebar-Titel folgt
    /// IMMER `detail.title` — Caller müssen kein Dual-Title-Wissen mehr tragen.
    func testUpdateDetailSyncsSidebarTitleFromDetailTitle() {
        let (summary, detail) = makeMeeting(id: "rec-002", title: "Aufnahme 09:00")
        store.insert(summary: summary, detail: detail)

        store.updateDetail(detail.with(title: "Q3-Budget-Review"))

        XCTAssertEqual(store.detail(for: "rec-002")?.title, "Q3-Budget-Review")
        XCTAssertEqual(store.meetings.first?.title, "Q3-Budget-Review",
                       "Sidebar-Titel muss dem Detail-Titel folgen")
    }

    func testUpdateDetailForUnknownIdIsSilentNoOp() {
        let (summary, detail) = makeMeeting(id: "rec-003", title: "Existiert")
        store.insert(summary: summary, detail: detail)

        let ghost = makeMeeting(id: "ghost", title: "Geist").1
        store.updateDetail(ghost)

        XCTAssertNil(store.detail(for: "ghost"), "updateDetail legt keine neuen Zeilen an")
        XCTAssertEqual(store.meetings.count, 1)
    }

    func testWorkspaceRoundTripKeepsMeetingAssignment() {
        let workspace = store.createWorkspace(
            name: " DAT ",
            kind: .organization,
            context: "UI/UX für den Kundenkontext."
        )

        let (summary, detail) = makeMeeting(
            id: "rec-workspace",
            title: "DAT Review",
            workspaceId: workspace?.id
        )
        store.insert(summary: summary, detail: detail)

        XCTAssertEqual(store.workspaces.first?.name, "DAT")
        XCTAssertEqual(store.workspaces.first?.kind, .organization)
        XCTAssertEqual(store.meetings.first?.workspaceId, workspace?.id)
        XCTAssertEqual(store.detail(for: "rec-workspace")?.workspaceId, workspace?.id)
    }

    func testAssignWorkspaceCanMoveAndClearMeeting() {
        let workspace = store.createWorkspace(name: "Mercedes", kind: .project)
        let (summary, detail) = makeMeeting(id: "rec-move", title: "Workshop")
        store.insert(summary: summary, detail: detail)

        store.assignWorkspace(meetingId: "rec-move", workspaceId: workspace?.id)
        XCTAssertEqual(store.meetings.first?.workspaceId, workspace?.id)

        store.assignWorkspace(meetingId: "rec-move", workspaceId: nil)
        XCTAssertNil(store.meetings.first?.workspaceId)
        XCTAssertNil(store.detail(for: "rec-move")?.workspaceId)
    }

    func testAssignWorkspaceCanMoveAndClearMultipleMeetings() {
        let workspace = store.createWorkspace(name: "E.ON", kind: .team)
        let first = makeMeeting(id: "rec-batch-a", title: "Kickoff")
        let second = makeMeeting(id: "rec-batch-b", title: "Review")
        let outside = makeMeeting(id: "rec-batch-outside", title: "Other")
        store.insert(summary: first.0, detail: first.1)
        store.insert(summary: second.0, detail: second.1)
        store.insert(summary: outside.0, detail: outside.1)

        store.assignWorkspace(
            meetingIds: ["rec-batch-a", "rec-batch-b"],
            workspaceId: workspace?.id
        )

        XCTAssertEqual(store.detail(for: "rec-batch-a")?.workspaceId, workspace?.id)
        XCTAssertEqual(store.detail(for: "rec-batch-b")?.workspaceId, workspace?.id)
        XCTAssertNil(store.detail(for: "rec-batch-outside")?.workspaceId)

        store.assignWorkspace(
            meetingIds: ["rec-batch-a", "rec-batch-b"],
            workspaceId: nil
        )

        XCTAssertNil(store.detail(for: "rec-batch-a")?.workspaceId)
        XCTAssertNil(store.detail(for: "rec-batch-b")?.workspaceId)
    }

    // MARK: - Recovery-Query

    func testMeetingsNeedingRecoveryFindsBusyMeetingsWithoutTranscript() {
        let (s1, d1) = makeMeeting(id: "stuck", title: "Hängt", lifecycle: .transcribing)
        let (s2, d2) = makeMeeting(id: "done", title: "Fertig", lifecycle: .done)
        store.insert(summary: s1, detail: d1)
        store.insert(summary: s2, detail: d2)

        XCTAssertEqual(store.meetingsNeedingRecovery(), ["stuck"])
    }

    func testMeetingsNeedingRecoverySkipsBusyMeetingsThatAlreadyHaveTranscript() {
        let (s, d) = makeMeeting(id: "busy-with-text", title: "Läuft", lifecycle: .summarizing)
        let line = TranscriptLine(who: "ME", timestamp: "00:00", body: "Schon transkribiert.")
        store.insert(summary: s, detail: d.with(transcript: [line]))

        XCTAssertTrue(store.meetingsNeedingRecovery().isEmpty,
                      "Meetings mit Transcript sind kein Recovery-Fall")
    }

    // MARK: - Versuchszähler

    func testTranscribeAttemptsBumpAndReset() {
        let (s, d) = makeMeeting(id: "rec-004", title: "Zähler")
        store.insert(summary: s, detail: d)

        XCTAssertEqual(store.transcribeAttempts(for: "rec-004"), 0)
        XCTAssertEqual(store.bumpTranscribeAttempts(for: "rec-004"), 1)
        XCTAssertEqual(store.bumpTranscribeAttempts(for: "rec-004"), 2)
        store.resetTranscribeAttempts(for: "rec-004")
        XCTAssertEqual(store.transcribeAttempts(for: "rec-004"), 0)
    }
}

/// Die 3-Strikes-Entscheidung — vorher im RecordingController verdrahtet,
/// während der Zähler im Store lebte.
final class TranscriptionRecoveryPolicyTests: XCTestCase {

    func testRetriesUpToMaxAttempts() {
        XCTAssertEqual(TranscriptionRecoveryPolicy.decision(forAttempt: 1), .retry)
        XCTAssertEqual(TranscriptionRecoveryPolicy.decision(forAttempt: 3), .retry)
    }

    func testMarksFailedBeyondMaxAttemptsWithNonBusyLifecycle() {
        let decision = TranscriptionRecoveryPolicy.decision(forAttempt: 4)
        guard case .markFailed(let lifecycle) = decision else {
            return XCTFail("Versuch 4 muss als gescheitert markieren")
        }
        XCTAssertFalse(lifecycle.isBusy,
                       ".failed darf nicht busy sein, sonst greift die Recovery es wieder auf")
        XCTAssertEqual(lifecycle, .failed(reason: "Transkription mehrfach unterbrochen", attempts: 3))
    }
}
