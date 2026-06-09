import XCTest
@testable import NeoQuill

/// Zoom-Timeline-Parsing läuft seit der Parser-Konsolidierung über den einen
/// `PlatformTranscriptParser.parseZoomTimeline`. Diese Fälle sichern die
/// users-spezifische Semantik (Sprecher-Pflicht, Platzhalter, confidence).
final class ZoomTimelineParsingTests: XCTestCase {
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
        """.data(using: .utf8)!
        let events = try PlatformTranscriptParser.parseZoomTimeline(json)
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
        """.data(using: .utf8)!
        let events = try PlatformTranscriptParser.parseZoomTimeline(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Lisa Müller")
        XCTAssertTrue(events[0].text.contains("Lisa Müller"))
        XCTAssertNil(events[0].rawPayload)
        XCTAssertEqual(events[0].confidence, 0.78, accuracy: 0.001)
    }

    func testEmptyTimelineReturnsNoEvents() throws {
        // Der Parser gibt bei leerer Quelle einfach keine Events zurück; ob das
        // ein Fehler ist, entscheidet PlatformImportService (ImportError.empty).
        let events = try PlatformTranscriptParser.parseZoomTimeline(Data("{ \"timeline\": [] }".utf8))
        XCTAssertTrue(events.isEmpty)
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
        """.data(using: .utf8)!
        let events = try PlatformTranscriptParser.parseZoomTimeline(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
    }
}
