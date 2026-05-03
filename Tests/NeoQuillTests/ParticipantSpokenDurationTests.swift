import XCTest
@testable import NeoQuill

final class ParticipantSpokenDurationTests: XCTestCase {

    func testFormatSpokeRoundsToWholeSeconds() {
        XCTAssertEqual(RecordingController.formatSpoke(seconds: 0), "0m 0s")
        XCTAssertEqual(RecordingController.formatSpoke(seconds: 47), "0m 47s")
        XCTAssertEqual(RecordingController.formatSpoke(seconds: 60), "1m 0s")
        XCTAssertEqual(RecordingController.formatSpoke(seconds: 707), "11m 47s")
        XCTAssertEqual(RecordingController.formatSpoke(seconds: 707.4), "11m 47s")
        XCTAssertEqual(RecordingController.formatSpoke(seconds: 707.6), "11m 48s")
    }

    func testFormatSpokeClampsNegativeSeconds() {
        XCTAssertEqual(RecordingController.formatSpoke(seconds: -10), "0m 0s")
    }

    func testDiarizationWinsOverLineDurationWhenAvailable() {
        let lines = [
            mockLine(who: "S1", start: 0, end: 5),
            mockLine(who: "S1", start: 10, end: 15),
            mockLine(who: "S2", start: 5, end: 10)
        ]
        let segments = [
            DiarizedSpeakerSegment(start: 0, end: 60, speakerId: "S1", embedding: []),
            DiarizedSpeakerSegment(start: 60, end: 120, speakerId: "S2", embedding: [])
        ]

        let result = RecordingController.spokenDurations(
            speakerIds: ["S1", "S2"],
            lines: lines,
            diarizationSegments: segments,
            fallback: "5m 0s"
        )

        XCTAssertEqual(result["S1"], "1m 0s")
        XCTAssertEqual(result["S2"], "1m 0s")
    }

    func testFallsBackToLineDurationWhenNoDiarization() {
        let lines = [
            mockLine(who: "S1", start: 0, end: 12),
            mockLine(who: "S1", start: 20, end: 30),
            mockLine(who: "S2", start: 30, end: 35)
        ]

        let result = RecordingController.spokenDurations(
            speakerIds: ["S1", "S2"],
            lines: lines,
            diarizationSegments: [],
            fallback: "10m 0s"
        )

        XCTAssertEqual(result["S1"], "0m 22s")
        XCTAssertEqual(result["S2"], "0m 5s")
    }

    func testUsesFallbackWhenSpeakerHasNeitherSegmentsNorLines() {
        let result = RecordingController.spokenDurations(
            speakerIds: ["ME", "S1"],
            lines: [],
            diarizationSegments: [],
            fallback: "8m 0s"
        )

        XCTAssertEqual(result["ME"], "8m 0s")
        XCTAssertEqual(result["S1"], "8m 0s")
    }

    func testDiarizationOnlySpeakerStillCounts() {
        let lines = [mockLine(who: "ME", start: 0, end: 30)]
        let segments = [
            DiarizedSpeakerSegment(start: 0, end: 25, speakerId: "S1", embedding: [])
        ]

        let result = RecordingController.spokenDurations(
            speakerIds: ["ME", "S1"],
            lines: lines,
            diarizationSegments: segments,
            fallback: "5m 0s"
        )

        XCTAssertEqual(result["S1"], "0m 25s")
        XCTAssertEqual(result["ME"], "0m 30s")
    }

    func testAggregatesMultipleSegmentsForSameSpeaker() {
        let segments = [
            DiarizedSpeakerSegment(start: 0, end: 12, speakerId: "S1", embedding: []),
            DiarizedSpeakerSegment(start: 30, end: 48, speakerId: "S1", embedding: []),
            DiarizedSpeakerSegment(start: 60, end: 90, speakerId: "S1", embedding: [])
        ]

        let result = RecordingController.spokenDurations(
            speakerIds: ["S1"],
            lines: [],
            diarizationSegments: segments,
            fallback: "0m 0s"
        )

        XCTAssertEqual(result["S1"], "1m 0s")
    }

    private func mockLine(who: String, start: TimeInterval, end: TimeInterval) -> TranscriptLine {
        TranscriptLine(
            who: who,
            timestamp: "00:00",
            startSeconds: start,
            endSeconds: end,
            body: "Test",
            source: .system,
            speakerSource: .diarization
        )
    }
}
