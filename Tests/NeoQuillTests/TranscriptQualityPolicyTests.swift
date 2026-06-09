import XCTest
@testable import NeoQuill

final class TranscriptQualityPolicyTests: XCTestCase {

    func testAcceptsPassedReport() {
        XCTAssertTrue(TranscriptQualityPolicy.accepts(report(status: .passed)))
    }

    func testRejectsFailedReport() {
        XCTAssertFalse(TranscriptQualityPolicy.accepts(report(status: .failed)))
    }

    func testEmptyTranscriptNeedsFallback() {
        let empty = report(status: .failed, segmentCount: 0, wordCount: 0, uniqueTextRatio: 0)
        XCTAssertTrue(TranscriptQualityPolicy.needsFallback(empty, audioSeconds: 30))
    }

    func testTooFewWordsForDurationNeedsFallback() {
        // 30 s Audio, 2 Wörter → unter max(4, 30/3 = 10).
        let thin = report(status: .passed, segmentCount: 1, wordCount: 2, uniqueTextRatio: 1)
        XCTAssertTrue(TranscriptQualityPolicy.needsFallback(thin, audioSeconds: 30))
    }

    func testShortClipBelowWordCheckFloorIgnoresWordCount() {
        // Unter 12 s greift die Wort-Schwelle nicht — 2 Wörter sind hier ok.
        let shortClip = report(status: .passed, segmentCount: 1, wordCount: 2, uniqueTextRatio: 1)
        XCTAssertFalse(TranscriptQualityPolicy.needsFallback(shortClip, audioSeconds: 8))
    }

    func testFailedStatusNeedsFallback() {
        let failed = report(status: .failed, segmentCount: 30, wordCount: 200, uniqueTextRatio: 1)
        XCTAssertTrue(TranscriptQualityPolicy.needsFallback(failed, audioSeconds: 60))
    }

    func testSmallScaleRepetitionNeedsFallback() {
        // 4 Zeilen, nur 1 unique (Ratio 0.25) → der Scorer flaggt das bei <20
        // Segmenten nicht, die Policy fängt es trotzdem ab.
        let loop = report(status: .passed, segmentCount: 4, wordCount: 8, uniqueTextRatio: 0.25)
        XCTAssertTrue(TranscriptQualityPolicy.needsFallback(loop, audioSeconds: 8))
    }

    func testHealthyTranscriptNeedsNoFallback() {
        let healthy = report(status: .passed, segmentCount: 6, wordCount: 54, uniqueTextRatio: 1)
        XCTAssertFalse(TranscriptQualityPolicy.needsFallback(healthy, audioSeconds: 12))
    }

    private func report(
        status: TranscriptQualityStatus,
        segmentCount: Int = 5,
        wordCount: Int = 50,
        uniqueTextRatio: Double = 1
    ) -> TranscriptQualityReport {
        TranscriptQualityReport(
            status: status,
            score: status == .passed ? 1 : 0,
            segmentCount: segmentCount,
            wordCount: wordCount,
            uniqueTextRatio: uniqueTextRatio,
            repeatRatio: 0,
            longestRepeatedRun: 1,
            warnings: []
        )
    }
}
