import XCTest
@testable import NeoQuill

final class MeetingTranscriberTests: XCTestCase {

    private let sut = MeetingTranscriber(whisperKitFallback: LiveTranscriber())

    func testWordCount() {
        let lines = [line("hallo welt"), line("drei vier fünf")]
        XCTAssertEqual(sut.wordCount(lines), 5)
    }

    func testEmptyTranscriptNeedsFallback() {
        XCTAssertTrue(sut.needsMixedFallback(lines: [], totalSamples: 16_000 * 30))
    }

    func testTooFewWordsNeedsFallback() {
        // 30 s Audio, aber nur 2 Wörter → unter max(4, 30/3 = 10)
        XCTAssertTrue(sut.needsMixedFallback(lines: [line("nur zwei")], totalSamples: 16_000 * 30))
    }

    func testHeavyRepetitionNeedsFallback() {
        // 4 identische Zeilen → uniqueTexts (1) <= count/2 (2)
        let lines = Array(repeating: line("vielen dank"), count: 4)
        XCTAssertTrue(sut.needsMixedFallback(lines: lines, totalSamples: 16_000 * 8))
    }

    func testHealthyTranscriptNeedsNoFallback() {
        // 12 s Audio, sechs inhaltlich verschiedene Zeilen mit genug Wörtern.
        let lines = (0..<6).map { i in
            line("das ist gesprochener satz nummer \(i) mit klarem inhalt")
        }
        XCTAssertFalse(sut.needsMixedFallback(lines: lines, totalSamples: 16_000 * 12))
    }

    private func line(_ body: String) -> TranscriptLine {
        TranscriptLine(who: "S1", timestamp: "00:00", body: body)
    }
}
