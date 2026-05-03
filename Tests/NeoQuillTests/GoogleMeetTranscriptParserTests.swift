import XCTest
@testable import NeoQuill

final class GoogleMeetTranscriptParserTests: XCTestCase {
    private let entriesJSON = """
    {
      "entries": [
        {
          "name": "conferenceRecords/abc/transcripts/xyz/entries/1",
          "participant": "conferenceRecords/abc/participants/p1",
          "text": "Willkommen zum Quartals-Meeting.",
          "languageCode": "de-DE",
          "startTime": "2026-05-03T09:00:00.000Z",
          "endTime": "2026-05-03T09:00:03.500Z"
        },
        {
          "name": "conferenceRecords/abc/transcripts/xyz/entries/2",
          "participant": "conferenceRecords/abc/participants/p2",
          "text": "Danke für die Einladung.",
          "languageCode": "de-DE",
          "startTime": "2026-05-03T09:00:04.000Z",
          "endTime": "2026-05-03T09:00:06.500Z"
        }
      ]
    }
    """

    private let participantsJSON = """
    [
      {
        "name": "conferenceRecords/abc/participants/p1",
        "user": { "displayName": "Sarah Ebner" }
      },
      {
        "name": "conferenceRecords/abc/participants/p2",
        "anonymousUser": { "displayName": "Externer Gast" }
      }
    ]
    """

    func testParsesEntriesAndResolvesParticipants() throws {
        let events = try GoogleMeetTranscriptParser.parse(
            entriesJSON: entriesJSON,
            participantsJSON: participantsJSON
        )
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].platform, .meet)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[0].speakerId, "conferenceRecords/abc/participants/p1")
        XCTAssertEqual(events[0].startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(events[0].endSeconds, 3.5, accuracy: 0.001)
        XCTAssertEqual(events[1].speakerName, "Externer Gast")
        XCTAssertEqual(events[1].startSeconds, 4.0, accuracy: 0.001)
    }

    func testParsesEntriesWithoutParticipantsKeepsResourceID() throws {
        let events = try GoogleMeetTranscriptParser.parse(entriesJSON: entriesJSON)
        XCTAssertEqual(events.count, 2)
        XCTAssertNil(events[0].speakerName)
        XCTAssertEqual(events[0].speakerId, "conferenceRecords/abc/participants/p1")
    }

    func testInvalidEntriesJSONThrows() {
        XCTAssertThrowsError(try GoogleMeetTranscriptParser.parse(entriesJSON: "{nope}")) { error in
            guard case PlatformParserError.invalidJSON = error else {
                XCTFail("Erwarteter Error war .invalidJSON, war: \(error)")
                return
            }
        }
    }

    func testEmptyEntriesArrayThrows() {
        let json = "{ \"entries\": [] }"
        XCTAssertThrowsError(try GoogleMeetTranscriptParser.parse(entriesJSON: json)) { error in
            XCTAssertEqual(error as? PlatformParserError, .empty)
        }
    }

    func testFallbackUsesSignedinUserDisplayName() throws {
        let entries = """
        {
          "entries": [
            {
              "participant": "conferenceRecords/x/participants/p1",
              "text": "Hi.",
              "startTime": "2026-05-03T09:00:00Z",
              "endTime": "2026-05-03T09:00:02Z"
            }
          ]
        }
        """
        let participants = """
        [
          {
            "name": "conferenceRecords/x/participants/p1",
            "signedinUser": { "displayName": "Lisa Müller" }
          }
        ]
        """
        let events = try GoogleMeetTranscriptParser.parse(
            entriesJSON: entries,
            participantsJSON: participants
        )
        XCTAssertEqual(events.first?.speakerName, "Lisa Müller")
    }
}
