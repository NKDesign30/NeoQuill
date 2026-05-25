import XCTest
@testable import NeoQuill

final class TranscriptQualityScorerTests: XCTestCase {
    func testRejectsLongRepeatedHallucinationRun() {
        let lines = (0..<120).map { index in
            TranscriptLine(
                who: "ME",
                timestamp: String(format: "%02d:%02d", index / 60, index % 60),
                startSeconds: TimeInterval(index),
                endSeconds: TimeInterval(index + 1),
                body: "Läufer-Splitter.",
                source: .mic,
                speakerSource: .microphoneOwner
            )
        }

        let report = TranscriptQualityScorer.evaluate(lines: lines, audioDurationSeconds: 7_200)

        XCTAssertEqual(report.status, .failed)
        XCTAssertTrue(report.warnings.contains(.longRepeatedRun))
        XCTAssertTrue(report.warnings.contains(.highRepeatRatio))
        XCTAssertTrue(report.warnings.contains(.lowUniqueTextRatio))
        XCTAssertGreaterThanOrEqual(report.longestRepeatedRun, 120)
        XCTAssertGreaterThan(report.repeatRatio, 0.9)
    }

    func testAllowsShortNaturalRepetitionWhenContentMovesOn() {
        let lines = [
            TranscriptLine(who: "ME", timestamp: "00:00", body: "Ja."),
            TranscriptLine(who: "ME", timestamp: "00:01", body: "Ja."),
            TranscriptLine(who: "ME", timestamp: "00:02", body: "Wir klären erst die Metadaten."),
            TranscriptLine(who: "S1", timestamp: "00:05", body: "Danach sprechen wir über die Suche."),
            TranscriptLine(who: "ME", timestamp: "00:08", body: "Ja."),
        ]

        let report = TranscriptQualityScorer.evaluate(lines: lines, audioDurationSeconds: 12)

        XCTAssertEqual(report.status, .passed)
        XCTAssertTrue(report.warnings.isEmpty)
    }

    func testTranscriptRunFromLinesStoresCanonicalSegments() {
        let lines = [
            TranscriptLine(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                who: "ME",
                displayName: "Niko Knez",
                timestamp: "01:23",
                startSeconds: 83,
                endSeconds: 86,
                body: "Lass uns über die Metadaten sprechen.",
                source: .mic,
                speakerSource: .microphoneOwner,
                confidence: 0.92
            )
        ]

        let run = TranscriptRun.fromLines(
            meetingId: "meeting-1",
            stem: "mic",
            audioSampleRate: 16_000,
            audioDurationSeconds: 120,
            engine: TranscriptEngineInfo(name: "WhisperKit", model: "small", version: nil),
            settings: TranscriptRunSettings(
                language: "de",
                maxContextTokens: 0,
                vadEnabled: false,
                fullJSON: false,
                chunkDurationSeconds: 120,
                overlapSeconds: 0
            ),
            lines: lines
        )

        XCTAssertEqual(run.schemaVersion, 2)
        XCTAssertEqual(run.segments.first?.speaker.source, .microphoneOwner)
        XCTAssertEqual(run.segments.first?.startMilliseconds, 83_000)
        XCTAssertEqual(run.transcriptLines().first?.body, lines.first?.body)
    }
}
