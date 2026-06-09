import XCTest
@testable import NeoQuill

/// Pinnt den Producer/Consumer-Vertrag fest, der vor der Konsolidierung über
/// fünf handgepflegte Kopien verteilt war: `stamp` erzeugt zwei-stellige
/// Minuten ohne Stundenrollung, `parse` liest das (und die drei-teilige Form)
/// verlustfrei zurück.
final class TranscriptTimecodeTests: XCTestCase {
    func testStampUsesZeroPaddedMinutesWithoutHourRollover() {
        XCTAssertEqual(TranscriptTimecode.stamp(0), "00:00")
        XCTAssertEqual(TranscriptTimecode.stamp(74), "01:14")
        // Bewusst keine Stundenrollung: 90 Minuten bleiben "90:00", nicht "1:30:00".
        XCTAssertEqual(TranscriptTimecode.stamp(5_400), "90:00")
    }

    func testStampClampsNegativeInput() {
        XCTAssertEqual(TranscriptTimecode.stamp(-5), "00:00")
    }

    func testStampTruncatesFractionalSeconds() {
        XCTAssertEqual(TranscriptTimecode.stamp(1.999), "00:01")
    }

    func testParseReadsTwoPartStamp() throws {
        try XCTAssertEqual(XCTUnwrap(TranscriptTimecode.parse("01:14")), 74, accuracy: 0.001)
        try XCTAssertEqual(XCTUnwrap(TranscriptTimecode.parse("2:14")), 134, accuracy: 0.001)
        try XCTAssertEqual(XCTUnwrap(TranscriptTimecode.parse("90:00")), 5_400, accuracy: 0.001)
    }

    func testParseReadsThreePartStamp() throws {
        try XCTAssertEqual(XCTUnwrap(TranscriptTimecode.parse("1:23:45")), 5_025, accuracy: 0.001)
    }

    func testParseReturnsNilForJunk() {
        XCTAssertNil(TranscriptTimecode.parse(""))
        XCTAssertNil(TranscriptTimecode.parse("abc"))
        XCTAssertNil(TranscriptTimecode.parse("12"))
        XCTAssertNil(TranscriptTimecode.parse("1:2:3:4"))
    }

    func testRoundTripAcrossMinuteBoundary() throws {
        for seconds in [0, 5, 59, 60, 61, 599, 600, 3_599, 5_400] {
            let stamped = TranscriptTimecode.stamp(TimeInterval(seconds))
            try XCTAssertEqual(XCTUnwrap(TranscriptTimecode.parse(stamped)), TimeInterval(seconds), accuracy: 0.001)
        }
    }
}
