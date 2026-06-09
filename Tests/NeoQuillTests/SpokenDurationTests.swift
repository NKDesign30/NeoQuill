import XCTest
@testable import NeoQuill

/// Sichert den Format/Parse-Round-Trip ab, der vorher über drei handgepflegte
/// Kopien verteilt war. Kern ist der Regressionstest für den Sub-Minuten-Bug:
/// die "45s"-Form muss zu 45 zurückparsen, nicht zu 0.
final class SpokenDurationTests: XCTestCase {
    func testMinutesSecondsAlwaysIncludesMinutesAndRounds() {
        XCTAssertEqual(SpokenDuration.minutesSeconds(0), "0m 0s")
        XCTAssertEqual(SpokenDuration.minutesSeconds(45), "0m 45s")
        XCTAssertEqual(SpokenDuration.minutesSeconds(707), "11m 47s")
        XCTAssertEqual(SpokenDuration.minutesSeconds(707.6), "11m 48s")
        XCTAssertEqual(SpokenDuration.minutesSeconds(-10), "0m 0s")
    }

    func testCompactDropsMinutesUnderOneMinuteAndTruncates() {
        XCTAssertEqual(SpokenDuration.compact(45), "45s")
        XCTAssertEqual(SpokenDuration.compact(45.9), "45s")
        XCTAssertEqual(SpokenDuration.compact(60), "1m 0s")
        XCTAssertEqual(SpokenDuration.compact(723), "12m 3s")
        XCTAssertEqual(SpokenDuration.compact(-10), "0s")
    }

    func testSecondsParsesBothFormsIncludingSubMinute() {
        XCTAssertEqual(SpokenDuration.seconds(from: "11m 47s"), 707)
        XCTAssertEqual(SpokenDuration.seconds(from: "0m 45s"), 45)
        // Der eigentliche Regressionsfall: kompakte Sub-Minuten-Form.
        XCTAssertEqual(SpokenDuration.seconds(from: "45s"), 45)
        // Null-gepaddete Variante (MockData).
        XCTAssertEqual(SpokenDuration.seconds(from: "14m 02s"), 842)
        // Minuten ohne Sekunden-Teil (war der einzige Mehrwert des alten
        // parseDuration für m/s-Formen).
        XCTAssertEqual(SpokenDuration.seconds(from: "12m"), 720)
    }

    func testSecondsReturnsNilForJunk() {
        XCTAssertNil(SpokenDuration.seconds(from: ""))
        XCTAssertNil(SpokenDuration.seconds(from: "   "))
        XCTAssertNil(SpokenDuration.seconds(from: "abc"))
    }

    func testCompactRoundTripSurvivesSubMinute() {
        for seconds in [0, 5, 45, 59, 60, 61, 723, 5_400] {
            let label = SpokenDuration.compact(TimeInterval(seconds))
            XCTAssertEqual(SpokenDuration.seconds(from: label), seconds, "round-trip für \(label)")
        }
    }

    func testMinutesSecondsRoundTrip() {
        for seconds in [0, 45, 60, 707] {
            let label = SpokenDuration.minutesSeconds(TimeInterval(seconds))
            XCTAssertEqual(SpokenDuration.seconds(from: label), seconds, "round-trip für \(label)")
        }
    }
}
