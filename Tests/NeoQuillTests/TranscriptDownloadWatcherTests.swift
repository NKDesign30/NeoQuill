import XCTest
@testable import NeoQuill

final class TranscriptDownloadWatcherTests: XCTestCase {

    // MARK: - detectHint

    @MainActor
    func testDetectsTeamsVTT() {
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "teams-transcript-2026-05-03.vtt"), .teamsVTT)
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "Teams_Meeting.vtt"), .teamsVTT)
    }

    @MainActor
    func testDetectsTeamsMetadata() {
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "teams-metadata.json"), .teamsMetadata)
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "Teams Meeting.json"), .teamsMetadata)
    }

    @MainActor
    func testDetectsMeetEntries() {
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "meet-transcript-12345.json"), .meetEntries)
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "google-meet-export.json"), .meetEntries)
    }

    @MainActor
    func testDetectsZoom() {
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "zoom-recording.vtt"), .zoomVTT)
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "zoom-timeline-2026.json"), .zoomTimeline)
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "zoom-cloud-export.json"), .zoomTimeline)
    }

    @MainActor
    func testGenericVTTFallback() {
        XCTAssertEqual(TranscriptDownloadWatcher.detectHint(filename: "irgendwas.vtt"), .generic)
    }

    @MainActor
    func testRejectsUnsupportedExtensions() {
        XCTAssertNil(TranscriptDownloadWatcher.detectHint(filename: "transcript.txt"))
        XCTAssertNil(TranscriptDownloadWatcher.detectHint(filename: "audio.mp3"))
        XCTAssertNil(TranscriptDownloadWatcher.detectHint(filename: "notes.md"))
    }

    // MARK: - recordingTimestamp

    @MainActor
    func testParsesRecordingTimestampWithPrefix() {
        XCTAssertEqual(TranscriptDownloadWatcher.recordingTimestamp(from: "rec-1714742400"), 1714742400)
    }

    @MainActor
    func testParsesRecordingTimestampWithoutPrefix() {
        XCTAssertEqual(TranscriptDownloadWatcher.recordingTimestamp(from: "1714742400"), 1714742400)
    }

    @MainActor
    func testReturnsNilForUnparseable() {
        XCTAssertNil(TranscriptDownloadWatcher.recordingTimestamp(from: "rec-not-a-number"))
        XCTAssertNil(TranscriptDownloadWatcher.recordingTimestamp(from: "manual-meeting"))
    }

    // MARK: - candidateMeetingIds

    @MainActor
    func testCandidatesAreFilteredByWindow() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let meetings = [
            mockSummary(id: "rec-1769990000"),  // -2.78h → out
            mockSummary(id: "rec-1769995000"),  // -1.39h → in
            mockSummary(id: "rec-1770003000"),  // +0.83h → in
            mockSummary(id: "rec-1770010000"),  // +2.78h → out
        ]
        let result = TranscriptDownloadWatcher.candidateMeetingIds(for: now, meetings: meetings)
        XCTAssertEqual(result, ["rec-1770003000", "rec-1769995000"])
    }

    @MainActor
    func testCandidatesIgnoreUnparseableIds() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let meetings = [
            mockSummary(id: "manual-meeting"),
            mockSummary(id: "rec-1770000500"),
        ]
        let result = TranscriptDownloadWatcher.candidateMeetingIds(for: now, meetings: meetings)
        XCTAssertEqual(result, ["rec-1770000500"])
    }

    @MainActor
    func testCandidatesSortedByDistance() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let meetings = [
            mockSummary(id: "rec-1770005000"),  // +83 min
            mockSummary(id: "rec-1770000100"),  // +1.6 min
            mockSummary(id: "rec-1769998000"),  // -33 min
        ]
        let result = TranscriptDownloadWatcher.candidateMeetingIds(for: now, meetings: meetings)
        XCTAssertEqual(result.first, "rec-1770000100")
        XCTAssertEqual(result.last, "rec-1770005000")
    }

    private func mockSummary(id: String) -> MeetingSummary {
        MeetingSummary(
            id: id,
            title: "Test",
            date: "01.01.",
            time: "10:00",
            duration: "10m",
            platform: .meet,
            wordCount: 0,
            group: "Test",
            participantIds: []
        )
    }
}
