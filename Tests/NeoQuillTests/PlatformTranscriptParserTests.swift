import XCTest
@testable import NeoQuill

final class PlatformTranscriptParserTests: XCTestCase {
    func testParsesTeamsWebVTTVoiceCue() {
        let vtt = """
        WEBVTT

        1
        00:00:01.000 --> 00:00:03.400
        <v Sarah Ebner>Wir starten mit dem Pricing.</v>
        """

        let events = PlatformTranscriptParser.parseWebVTT(vtt, platform: .teams)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[0].text, "Wir starten mit dem Pricing.")
        XCTAssertEqual(events[0].startSeconds, 1.0, accuracy: 0.001)
        XCTAssertEqual(events[0].endSeconds, 3.4, accuracy: 0.001)
    }

    func testParsesTeamsMetadataContentRelativeToFirstEntry() throws {
        let json = """
        {
          "entries": [
            {
              "speakerName": "Mara Becker",
              "spokenText": "Das ist der erste Punkt.",
              "startDateTime": "2026-05-03T10:00:02.000Z",
              "endDateTime": "2026-05-03T10:00:05.000Z"
            },
            {
              "speakerName": "Tom Leitner",
              "spokenText": "Ich übernehme das.",
              "startDateTime": "2026-05-03T10:00:08.000Z",
              "endDateTime": "2026-05-03T10:00:10.000Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let events = try PlatformTranscriptParser.parseTeamsMetadataContent(json)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].speakerName, "Mara Becker")
        XCTAssertEqual(events[0].startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(events[1].speakerName, "Tom Leitner")
        XCTAssertEqual(events[1].startSeconds, 6, accuracy: 0.001)
    }

    func testParsesGoogleMeetEntriesWithParticipants() throws {
        let entries = """
        {
          "transcriptEntries": [
            {
              "participant": "conferenceRecords/abc/participants/p1",
              "text": "Ich schreibe das ins Protokoll.",
              "startTime": "2026-05-03T11:20:00Z",
              "endTime": "2026-05-03T11:20:03Z"
            }
          ]
        }
        """.data(using: .utf8)!
        let participants = """
        {
          "participants": [
            {
              "name": "conferenceRecords/abc/participants/p1",
              "signedinUser": {
                "displayName": "Julia Brandt"
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let events = try PlatformTranscriptParser.parseGoogleMeetEntries(
            entriesData: entries,
            participantsData: participants
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].platform, .meet)
        XCTAssertEqual(events[0].speakerName, "Julia Brandt")
        XCTAssertEqual(events[0].speakerId, "conferenceRecords/abc/participants/p1")
        XCTAssertEqual(events[0].startSeconds, 0, accuracy: 0.001)
    }

    func testParsesZoomTimeline() throws {
        let json = """
        {
          "timeline": [
            {
              "speaker_name": "Chris Wagner",
              "user_id": "zoom-user-1",
              "text": "Rollout bleibt bei Freitag.",
              "start_time": 12.5,
              "end_time": 15.0
            }
          ]
        }
        """.data(using: .utf8)!

        let events = try PlatformTranscriptParser.parseZoomTimeline(json)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].platform, .zoom)
        XCTAssertEqual(events[0].speakerName, "Chris Wagner")
        XCTAssertEqual(events[0].speakerId, "zoom-user-1")
        XCTAssertEqual(events[0].startSeconds, 12.5, accuracy: 0.001)
    }

    func testZoomTimelineHandlesEndTsField() throws {
        let json = """
        {
          "timeline": [
            {
              "speaker_name": "Chris Wagner",
              "user_id": "zoom-user-1",
              "text": "Rollout bleibt bei Freitag.",
              "ts": "2026-05-03T12:00:00.000Z",
              "end_ts": "2026-05-03T12:00:04.500Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let events = try PlatformTranscriptParser.parseZoomTimeline(json)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].platform, .zoom)
        XCTAssertEqual(events[0].startSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(events[0].endSeconds, 4.5, accuracy: 0.001)
    }

    func testZoomTimelineExtractsActiveUserFromUsersArray() throws {
        let json = """
        {
          "timeline": [
            {
              "ts": "2026-05-03T12:00:00.000Z",
              "end_ts": "2026-05-03T12:00:02.000Z",
              "text": "Ich nehme das mit.",
              "users": [
                { "user_id": "u-passive", "user_name": "Stille Beobachterin", "talking": false },
                { "user_id": "u-active", "user_name": "Chris Wagner", "talking": true }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let events = try PlatformTranscriptParser.parseZoomTimeline(json)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Chris Wagner")
        XCTAssertEqual(events[0].speakerId, "u-active")
    }

    func testTeamsSpecificParserReadsVTT() throws {
        let vtt = """
        WEBVTT

        00:00:02.000 --> 00:00:04.000
        Mara Becker: Entscheidung steht.
        """

        let events = try TeamsTranscriptParser.fromVTT(vtt)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].platform, .teams)
        XCTAssertEqual(events[0].speakerName, "Mara Becker")
        XCTAssertEqual(events[0].text, "Entscheidung steht.")
    }

    func testZoomSpecificTimelineParserReadsActiveUser() throws {
        let json = """
        {
          "timeline": [
            {
              "ts": "2026-05-03T12:00:00Z",
              "end_ts": "2026-05-03T12:00:02Z",
              "text": "Ich nehme das mit.",
              "users": [
                {
                  "user_id": "z1",
                  "user_name": "Chris Wagner",
                  "talking": true
                }
              ]
            }
          ]
        }
        """

        let events = try ZoomTranscriptParser.fromTimeline(json)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].speakerName, "Chris Wagner")
        XCTAssertEqual(events[0].speakerId, "z1")
        XCTAssertEqual(events[0].startSeconds, 0, accuracy: 0.001)
    }
}
