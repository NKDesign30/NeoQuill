import XCTest
@testable import NeoQuill

final class PlatformImportServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neoquill-import-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, _ content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testDetectsTeamsVTTViaVoiceTag() throws {
        let url = try write("session.vtt", """
        WEBVTT

        00:00:01.000 --> 00:00:04.000
        <v Sarah Ebner>Wir starten gleich.
        """)
        let outcome = try PlatformImportService.detectAndParse(url: url)
        XCTAssertEqual(outcome.platform, .teams)
        XCTAssertEqual(outcome.events.count, 1)
        XCTAssertEqual(outcome.events[0].speakerName, "Sarah Ebner")
    }

    func testDetectsTeamsMetadataJSON() throws {
        let url = try write("teams-metadata.json", """
        {
          "value": [
            {
              "spokenText": "Demo läuft.",
              "speakerName": "Mara Becker",
              "startDateTime": "2026-05-03T10:00:00Z",
              "endDateTime": "2026-05-03T10:00:03Z"
            }
          ]
        }
        """)
        let outcome = try PlatformImportService.detectAndParse(url: url)
        XCTAssertEqual(outcome.platform, .teams)
        XCTAssertEqual(outcome.events.first?.speakerName, "Mara Becker")
    }

    func testDetectsMeetEntriesJSON() throws {
        let url = try write("meet-entries.json", """
        {
          "transcriptEntries": [
            {
              "participant": "conferenceRecords/abc/participants/p1",
              "text": "Hi.",
              "startTime": "2026-05-03T11:00:00Z",
              "endTime": "2026-05-03T11:00:02Z"
            }
          ]
        }
        """)
        let outcome = try PlatformImportService.detectAndParse(url: url)
        XCTAssertEqual(outcome.platform, .meet)
        XCTAssertEqual(outcome.events.first?.speakerId, "conferenceRecords/abc/participants/p1")
    }

    func testDetectsZoomTimelineWithUsersArray() throws {
        let url = try write("zoom-timeline.json", """
        {
          "timeline": [
            {
              "ts": "2026-05-03T12:00:00Z",
              "end_ts": "2026-05-03T12:00:02Z",
              "text": "Demo läuft.",
              "users": [
                { "user_id": "u1", "user_name": "Chris Wagner", "talking": true }
              ]
            }
          ]
        }
        """)
        let outcome = try PlatformImportService.detectAndParse(url: url)
        XCTAssertEqual(outcome.platform, .zoom)
        XCTAssertEqual(outcome.events.first?.speakerName, "Chris Wagner")
    }

    func testDetectsZoomTimelineWithoutUsers() throws {
        let url = try write("zoom-flat.json", """
        {
          "timeline": [
            {
              "speaker_name": "Anna Steiner",
              "user_id": "u9",
              "text": "Sprint-Goal hat gehalten.",
              "ts": "2026-05-03T12:00:00Z",
              "end_ts": "2026-05-03T12:00:03Z"
            }
          ]
        }
        """)
        let outcome = try PlatformImportService.detectAndParse(url: url)
        XCTAssertEqual(outcome.platform, .zoom)
        XCTAssertEqual(outcome.events.first?.speakerName, "Anna Steiner")
        XCTAssertEqual(outcome.events.first?.endSeconds ?? 0, 3, accuracy: 0.001)
    }

    func testEmptyJSONThrowsEmpty() throws {
        let url = try write("teams-metadata.json", """
        { "value": [] }
        """)
        XCTAssertThrowsError(try PlatformImportService.detectAndParse(url: url)) { error in
            XCTAssertEqual(error as? PlatformImportService.ImportError, .empty)
        }
    }

    func testUnsupportedExtensionThrows() throws {
        let url = try write("transcript.txt", "Sarah: hi\n")
        XCTAssertThrowsError(try PlatformImportService.detectAndParse(url: url)) { error in
            XCTAssertEqual(error as? PlatformImportService.ImportError, .unsupportedFormat)
        }
    }

    func testUnknownJSONShapeThrowsUnsupported() throws {
        let url = try write("garbage.json", "{ \"foo\": \"bar\" }")
        XCTAssertThrowsError(try PlatformImportService.detectAndParse(url: url)) { error in
            XCTAssertEqual(error as? PlatformImportService.ImportError, .unsupportedFormat)
        }
    }

    func testFilenameHintFallbackForGenericVTT() throws {
        let url = try write("zoom-cloud-recording.vtt", """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        Anna Steiner: Erster Punkt.
        """)
        let outcome = try PlatformImportService.detectAndParse(url: url)
        XCTAssertEqual(outcome.platform, .zoom)
        XCTAssertEqual(outcome.events.first?.speakerName, "Anna Steiner")
    }
}
