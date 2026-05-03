import XCTest
@testable import NeoQuill

final class TeamsTranscriptParserTests: XCTestCase {
    func testVTTParsesVoiceTagsAndPreservesTiming() throws {
        let raw = """
        WEBVTT

        00:00:00.500 --> 00:00:03.250
        <v Sarah Ebner>Wir starten mit dem Status-Update.

        00:00:03.500 --> 00:00:07.000
        <v Tom Friedrich>Sprint-Goal hat gehalten, Demo am Donnerstag.
        """
        let events = try TeamsTranscriptParser.fromVTT(raw)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].platform, .teams)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[0].text, "Wir starten mit dem Status-Update.")
        XCTAssertEqual(events[0].startSeconds, 0.5, accuracy: 0.001)
        XCTAssertEqual(events[0].endSeconds, 3.25, accuracy: 0.001)
        XCTAssertEqual(events[0].confidence, 0.9, accuracy: 0.001)
        XCTAssertEqual(events[1].speakerName, "Tom Friedrich")
    }

    func testVTTFallbackUsesColonPrefix() throws {
        let raw = """
        WEBVTT

        00:00:01.000 --> 00:00:02.500
        Sarah Ebner: Kurz noch zur Doku.
        """
        let events = try TeamsTranscriptParser.fromVTT(raw)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[0].text, "Kurz noch zur Doku.")
    }

    func testEmptyVTTThrows() {
        XCTAssertThrowsError(try TeamsTranscriptParser.fromVTT("   \n  ")) { error in
            XCTAssertEqual(error as? PlatformParserError, .empty)
        }
    }

    func testMetadataContentParsesValueArrayWithAbsoluteTimestamps() throws {
        let json = """
        {
          "value": [
            {
              "spokenText": "Hallo zusammen, Sprint-Demo startet jetzt.",
              "speakerName": "Sarah Ebner",
              "speakerId": "user-001",
              "startDateTime": "2026-05-03T10:00:00.000Z",
              "endDateTime": "2026-05-03T10:00:03.500Z",
              "spokenLanguage": "de-DE"
            },
            {
              "spokenText": "Bin dabei, mein Mic ist an.",
              "speakerName": "Tom Friedrich",
              "speakerId": "user-002",
              "startDateTime": "2026-05-03T10:00:04.000Z",
              "endDateTime": "2026-05-03T10:00:07.000Z"
            }
          ]
        }
        """
        let events = try TeamsTranscriptParser.fromMetadataContent(json)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[0].speakerId, "user-001")
        XCTAssertEqual(events[0].startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(events[0].endSeconds, 3.5, accuracy: 0.001)
        XCTAssertEqual(events[1].startSeconds, 4.0, accuracy: 0.001)
        XCTAssertEqual(events[1].endSeconds, 7.0, accuracy: 0.001)
        XCTAssertEqual(events[0].confidence, 0.96, accuracy: 0.001)
    }

    func testMetadataContentAcceptsTopLevelArray() throws {
        let json = """
        [
          {
            "spokenText": "Erste Zeile",
            "startDateTime": "2026-05-03T10:00:00Z",
            "endDateTime": "2026-05-03T10:00:02Z",
            "speakerName": "Sarah Ebner"
          }
        ]
        """
        let events = try TeamsTranscriptParser.fromMetadataContent(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].text, "Erste Zeile")
    }

    func testMetadataContentInvalidJSONThrows() {
        XCTAssertThrowsError(try TeamsTranscriptParser.fromMetadataContent("{not json")) { error in
            guard case PlatformParserError.invalidJSON = error else {
                XCTFail("Erwarteter Error war .invalidJSON, war: \(error)")
                return
            }
        }
    }

    func testMetadataContentRespectsExternalReferenceDate() throws {
        let json = """
        [
          {
            "spokenText": "Mitten im Meeting",
            "startDateTime": "2026-05-03T10:05:00Z",
            "endDateTime": "2026-05-03T10:05:04Z",
            "speakerName": "Sarah Ebner"
          }
        ]
        """
        let reference = ISO8601DateFormatter().date(from: "2026-05-03T10:00:00Z")!
        let events = try TeamsTranscriptParser.fromMetadataContent(json, referenceDate: reference)
        XCTAssertEqual(events[0].startSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(events[0].endSeconds, 304, accuracy: 0.001)
    }
}
