import XCTest
@testable import NeoQuill

final class MeetingExporterTranscriptJSONTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingExporterTranscriptJSONTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testArchiveExportWritesCanonicalTranscriptJSONNextToMarkdown() throws {
        let meeting = MeetingDetail(
            id: "meeting-\(UUID().uuidString)",
            title: "Transcript JSON",
            dateLong: "Montag, 25. Mai",
            timeRange: "12:00 - 12:03",
            duration: "3m",
            platform: .call,
            wordCount: 4,
            participants: [
                Participant(id: "ME", name: "Niko Knez", role: "Host", colorHex: 0x2EAB73, spoke: "3m")
            ],
            tldr: "Kurz.",
            highlights: [],
            tasks: [],
            chapters: [],
            transcript: [
                TranscriptLine(
                    who: "ME",
                    displayName: "Niko Knez",
                    timestamp: "00:01",
                    startSeconds: 1,
                    endSeconds: 3,
                    body: "Guter JSON Export.",
                    source: .mic,
                    speakerSource: .microphoneOwner
                )
            ]
        )

        let folder = try MeetingExporter.exportArchive([meeting], to: tempDirectory, now: Date(timeIntervalSince1970: 0))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        let jsonName = try XCTUnwrap(files.first { $0.hasSuffix(".transcript.json") })
        XCTAssertNotNil(files.first { $0.hasSuffix(".md") })

        let jsonURL = folder.appendingPathComponent(jsonName)
        let run = try JSONDecoder.iso8601.decode(TranscriptRun.self, from: Data(contentsOf: jsonURL))
        XCTAssertEqual(run.schemaVersion, 2)
        XCTAssertEqual(run.meetingId, meeting.id)
        XCTAssertEqual(run.segments.first?.text, "Guter JSON Export.")
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
