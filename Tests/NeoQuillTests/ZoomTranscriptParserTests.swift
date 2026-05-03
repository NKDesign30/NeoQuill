import XCTest
@testable import NeoQuill

final class ZoomTranscriptParserTests: XCTestCase {
    func testParsesIndexedColonStyleVTT() throws {
        let raw = """
        WEBVTT

        1
        00:00:00.040 --> 00:00:01.700
        Sarah Ebner: Hallo zusammen.

        2
        00:00:01.800 --> 00:00:04.500
        Tom Friedrich: Hi Sarah, alle hörbar.
        """
        let events = try ZoomTranscriptParser.fromVTT(raw)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].platform, .zoom)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[0].text, "Hallo zusammen.")
        XCTAssertEqual(events[0].startSeconds, 0.04, accuracy: 0.001)
        XCTAssertEqual(events[1].speakerName, "Tom Friedrich")
        XCTAssertEqual(events[1].endSeconds, 4.5, accuracy: 0.001)
    }

    func testParsesTimelineWithRelativeOffsets() throws {
        let json = """
        {
          "timeline": [
            {
              "ts": "2026-05-03T11:00:00.000Z",
              "end_ts": "2026-05-03T11:00:03.000Z",
              "users": [
                { "user_id": "u1", "user_name": "Sarah Ebner", "talking": true }
              ],
              "text": "Wir starten."
            },
            {
              "ts": "2026-05-03T11:00:04.000Z",
              "end_ts": "2026-05-03T11:00:06.500Z",
              "users": [
                { "user_id": "u2", "user_name": "Tom Friedrich", "talking": true }
              ],
              "text": "Bin dabei."
            }
          ]
        }
        """
        let events = try ZoomTranscriptParser.fromTimeline(json)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].platform, .zoom)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[0].speakerId, "u1")
        XCTAssertEqual(events[0].startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(events[1].startSeconds, 4.0, accuracy: 0.001)
    }

    func testTimelineUsesPlaceholderTextWhenMissing() throws {
        let json = """
        [
          {
            "ts": "2026-05-03T11:00:00Z",
            "users": [
              { "user_id": "u3", "user_name": "Lisa Müller" }
            ]
          }
        ]
        """
        let events = try ZoomTranscriptParser.fromTimeline(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Lisa Müller")
        XCTAssertTrue(events[0].text.contains("Lisa Müller"))
        XCTAssertNil(events[0].rawPayload)
        XCTAssertEqual(events[0].confidence, 0.78, accuracy: 0.001)
    }

    func testEmptyTimelineThrows() {
        XCTAssertThrowsError(try ZoomTranscriptParser.fromTimeline("{ \"timeline\": [] }")) { error in
            XCTAssertEqual(error as? PlatformParserError, .empty)
        }
    }

    func testTimelineSkipsEntriesWithoutSpeaker() throws {
        let json = """
        {
          "timeline": [
            {
              "ts": "2026-05-03T11:00:00Z",
              "users": [],
              "text": "Niemand spricht."
            },
            {
              "ts": "2026-05-03T11:00:05Z",
              "users": [{ "user_id": "u1", "user_name": "Sarah Ebner" }],
              "text": "Hallo."
            }
          ]
        }
        """
        let events = try ZoomTranscriptParser.fromTimeline(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
    }
}
