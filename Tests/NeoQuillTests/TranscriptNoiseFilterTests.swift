import XCTest
@testable import NeoQuill

final class TranscriptNoiseFilterTests: XCTestCase {
    func testDropsConsecutiveRepeatedBodiesAfterSecondOccurrence() {
        let lines = (0..<5).map { index in
            TranscriptLine(who: "ME", timestamp: "00:0\(index)", body: "Läufer-Splitter.")
        }

        let filtered = TranscriptNoiseFilter.filtered(lines)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.map(\.timestamp), ["00:00", "00:01"])
    }

    func testKeepsSameBodyWhenRealContentBreaksTheRun() {
        let lines = [
            TranscriptLine(who: "ME", timestamp: "00:00", body: "Ja."),
            TranscriptLine(who: "ME", timestamp: "00:01", body: "Ja."),
            TranscriptLine(who: "ME", timestamp: "00:02", body: "Nächster Punkt."),
            TranscriptLine(who: "ME", timestamp: "00:03", body: "Ja."),
        ]

        let filtered = TranscriptNoiseFilter.filtered(lines)

        XCTAssertEqual(filtered.map(\.body), ["Ja.", "Ja.", "Nächster Punkt.", "Ja."])
    }

    func testWordCountUsesFilteredLinesShape() {
        let lines = [
            TranscriptLine(who: "ME", timestamp: "00:00", body: "Ein zwei"),
            TranscriptLine(who: "ME", timestamp: "00:01", body: "drei"),
        ]

        XCTAssertEqual(TranscriptNoiseFilter.wordCount(lines), 3)
    }
}
