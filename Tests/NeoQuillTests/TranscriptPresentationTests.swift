import XCTest
@testable import NeoQuill

final class TranscriptPresentationTests: XCTestCase {
    func testCollapsedRowsRepresentLongRepeatedRunsWithoutDroppingRawCount() {
        let repeated = (0..<10).map { index in
            TranscriptLine(who: "ME", timestamp: "00:\(String(format: "%02d", index))", body: "Läufer-Splitter.")
        }

        let rows = TranscriptPresentation.rows(from: repeated, mode: .collapsedRepeatedRuns)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.representedLineCount }, repeated.count)
        guard case .collapsedRun(_, let hiddenCount) = rows[2].kind else {
            XCTFail("Expected repeated run to collapse")
            return
        }
        XCTAssertEqual(hiddenCount, 8)
    }

    func testRawRowsKeepEveryLineVisible() {
        let lines = [
            TranscriptLine(who: "ME", timestamp: "00:00", body: "Ja."),
            TranscriptLine(who: "ME", timestamp: "00:01", body: "Ja."),
            TranscriptLine(who: "ME", timestamp: "00:02", body: "Ja.")
        ]

        let rows = TranscriptPresentation.rows(from: lines, mode: .raw)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.representedLineCount }, 3)
    }

    func testFilteredRowsSearchCollapsedRunText() {
        let lines = (0..<4).map { index in
            TranscriptLine(who: "ME", timestamp: "00:\(String(format: "%02d", index))", body: "Budget bleibt offen.")
        }
        let rows = TranscriptPresentation.rows(from: lines, mode: .collapsedRepeatedRuns)

        XCTAssertEqual(TranscriptPresentation.filteredRows(rows, query: "budget").count, rows.count)
        XCTAssertTrue(TranscriptPresentation.filteredRows(rows, query: "launch").isEmpty)
    }
}
