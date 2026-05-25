import XCTest
@testable import NeoQuill

final class TranscriptRunStoreTests: XCTestCase {
    func testWritesAndReadsCanonicalRunJSON() throws {
        let meetingId = "meeting-\(UUID().uuidString)"
        let run = TranscriptRun.fromLines(
            meetingId: meetingId,
            stem: "mic",
            audioSampleRate: 16_000,
            audioDurationSeconds: 20,
            engine: TranscriptEngineInfo(name: "whisper.cpp", model: "large-v3-turbo", version: nil),
            settings: TranscriptRunSettings(
                language: "de",
                maxContextTokens: 0,
                vadEnabled: true,
                fullJSON: true,
                chunkDurationSeconds: 600,
                overlapSeconds: 0
            ),
            lines: [
                TranscriptLine(who: "ME", timestamp: "00:01", startSeconds: 1, endSeconds: 3, body: "Guter Test.")
            ]
        )

        let url = try TranscriptRunStore.write(run)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }

        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"schemaVersion\" : 2"))
        XCTAssertTrue(raw.contains("\"quality\""))

        let runs = try TranscriptRunStore.readRuns(meetingId: meetingId)
        XCTAssertTrue(runs.contains { $0.id == run.id })
        XCTAssertEqual(runs.first(where: { $0.id == run.id })?.segments.first?.text, "Guter Test.")
    }
}
