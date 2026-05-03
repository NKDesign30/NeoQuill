import XCTest
@testable import NeoQuill

final class VTTCueParserTests: XCTestCase {
    func testParsesSimpleVoiceTagBlock() {
        let raw = """
        WEBVTT

        00:00:01.500 --> 00:00:04.000
        <v Sarah Ebner>Wir starten mit dem Roll-out am Freitag.

        00:00:04.500 --> 00:00:07.250
        <v Tom Friedrich>Klingt gut, ich übernehme die Doku.
        """

        let cues = VTTCueParser.parse(raw)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].voiceTagName, "Sarah Ebner")
        XCTAssertEqual(cues[0].voiceTagText, "Wir starten mit dem Roll-out am Freitag.")
        XCTAssertEqual(cues[0].startSeconds, 1.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].endSeconds, 4.0, accuracy: 0.001)
        XCTAssertEqual(cues[1].voiceTagName, "Tom Friedrich")
    }

    func testParsesColonSpeakerCue() {
        let raw = """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        Sarah Ebner: Hallo zusammen.
        """
        let cues = VTTCueParser.parse(raw)
        XCTAssertEqual(cues.count, 1)
        XCTAssertNil(cues[0].voiceTagName)
        XCTAssertEqual(cues[0].colonSpeakerPrefix?.speaker, "Sarah Ebner")
        XCTAssertEqual(cues[0].colonSpeakerPrefix?.text, "Hallo zusammen.")
    }

    func testParsesIndexedZoomCue() {
        let raw = """
        WEBVTT

        1
        00:00:00.040 --> 00:00:02.700
        Sarah Ebner: Erste Aussage.

        2
        00:00:02.800 --> 00:00:05.000
        Tom Friedrich: Antwort folgt.
        """
        let cues = VTTCueParser.parse(raw)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].colonSpeakerPrefix?.speaker, "Sarah Ebner")
        XCTAssertEqual(cues[1].startSeconds, 2.8, accuracy: 0.001)
    }

    func testParsesTimestampWithoutHours() {
        let raw = """
        WEBVTT

        12:34.250 --> 12:36.500
        Test ohne Stunden.
        """
        let cues = VTTCueParser.parse(raw)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].startSeconds, 754.25, accuracy: 0.001)
        XCTAssertEqual(cues[0].endSeconds, 756.5, accuracy: 0.001)
    }

    func testIgnoresMalformedTiming() {
        let raw = """
        WEBVTT

        00:00:01 to 00:00:05
        Kaputter Block.

        00:00:02.000 --> 00:00:04.000
        Korrekter Block.
        """
        let cues = VTTCueParser.parse(raw)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].payload, "Korrekter Block.")
    }

    func testParseTimestampReturnsNilForJunk() {
        XCTAssertNil(VTTCueParser.parseTimestamp("not-a-time"))
        XCTAssertNil(VTTCueParser.parseTimestamp("99"))
    }
}
