import XCTest
@testable import NeoQuill

final class TranscriptPagingTests: XCTestCase {
    func testInitialVisibleCountUsesPageSizeForLargeTranscript() {
        XCTAssertEqual(TranscriptPaging.visibleCount(total: 7_000, requested: TranscriptPaging.pageSize), 50)
    }

    func testVisibleCountClampsToShortTranscript() {
        XCTAssertEqual(TranscriptPaging.visibleCount(total: 12, requested: TranscriptPaging.pageSize), 12)
    }

    func testNextCountAdvancesByOnePageAndClampsAtTotal() {
        XCTAssertEqual(TranscriptPaging.nextCount(current: 50, total: 7_000), 100)
        XCTAssertEqual(TranscriptPaging.nextCount(current: 90, total: 120), 120)
    }

    func testHasMoreReflectsRemainingRows() {
        XCTAssertTrue(TranscriptPaging.hasMore(visibleCount: 50, total: 7_000))
        XCTAssertFalse(TranscriptPaging.hasMore(visibleCount: 120, total: 120))
    }

    func testFilteredLinesMatchesCaseAndDiacriticsInsensitively() {
        let lines = [
            TranscriptLine(who: "ME", timestamp: "00:00", body: "Über den Launch sprechen."),
            TranscriptLine(who: "S1", timestamp: "00:03", body: "Budget bleibt offen."),
        ]

        let filtered = TranscriptPaging.filteredLines(lines, query: "uber")

        XCTAssertEqual(filtered.map(\.who), ["ME"])
    }

    func testFilteredLinesReturnsAllRowsForEmptyQuery() {
        let lines = [
            TranscriptLine(who: "ME", timestamp: "00:00", body: "Erste Zeile."),
            TranscriptLine(who: "S1", timestamp: "00:03", body: "Zweite Zeile."),
        ]

        XCTAssertEqual(TranscriptPaging.filteredLines(lines, query: "   "), lines)
    }
}
