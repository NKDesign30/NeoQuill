import XCTest
@testable import NeoQuill

final class DiarizationFilteringTests: XCTestCase {

    func testShortSegmentBelowThresholdIsIgnored() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:05",
            startSeconds: 5,
            endSeconds: 8,
            body: "Wir starten mit dem Pricing-Punkt.",
            source: .system,
            speakerSource: .unknown
        )
        let shortNoise = DiarizedSpeakerSegment(
            start: 5.0,
            end: 5.4,
            speakerId: "S2",
            embedding: [0.1, 0.2, 0.3]
        )

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [],
            diarization: [shortNoise]
        )

        XCTAssertEqual(merged.first?.who, "S1", "Mini-Segment darf Speaker nicht überschreiben")
        XCTAssertEqual(merged.first?.speakerSource, .unknown)
    }

    func testSegmentExactlyAtThresholdIsAccepted() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:00",
            startSeconds: 0,
            endSeconds: 3,
            body: "Bitte starte die Aufzeichnung.",
            source: .system,
            speakerSource: .unknown
        )
        let segment = DiarizedSpeakerSegment(
            start: 0,
            end: TranscriptMerger.minDiarizationMatchDuration,
            speakerId: "S2",
            embedding: [0.4, 0.5, 0.6]
        )

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [],
            diarization: [segment]
        )

        XCTAssertEqual(merged.first?.who, "S2")
        XCTAssertEqual(merged.first?.speakerSource, .diarization)
    }

    func testLongerSegmentIsPreferredOverNoiseAtSameTime() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:10",
            startSeconds: 10,
            endSeconds: 14,
            body: "Wir gehen das Backlog durch.",
            source: .system,
            speakerSource: .unknown
        )
        let noise = DiarizedSpeakerSegment(
            start: 10.0,
            end: 10.3,
            speakerId: "S3",
            embedding: [0.0, 0.0, 0.0]
        )
        let realSpeaker = DiarizedSpeakerSegment(
            start: 10.2,
            end: 13.8,
            speakerId: "S2",
            embedding: [0.1, 0.1, 0.1]
        )

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [],
            diarization: [noise, realSpeaker]
        )

        XCTAssertEqual(merged.first?.who, "S2", "Längstes Segment muss gewinnen, kurzes Noise ignoriert")
    }

    func testAllShortSegmentsLeaveLineUntouched() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:20",
            startSeconds: 20,
            endSeconds: 24,
            body: "Wer hat das Ticket übernommen?",
            source: .system,
            speakerSource: .unknown
        )
        let segments = [
            DiarizedSpeakerSegment(start: 20.0, end: 20.4, speakerId: "S2", embedding: []),
            DiarizedSpeakerSegment(start: 21.0, end: 21.3, speakerId: "S3", embedding: []),
            DiarizedSpeakerSegment(start: 22.0, end: 22.5, speakerId: "S4", embedding: [])
        ]

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [],
            diarization: segments
        )

        XCTAssertEqual(merged.first?.who, "S1")
        XCTAssertEqual(merged.first?.speakerSource, .unknown)
    }
}
