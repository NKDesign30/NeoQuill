import XCTest
@testable import NeoQuill

/// Die Playback-Auflösungs-Kette (decide → render → Rate-Fallback) mit
/// injiziertem Render-Schritt — vorher war genau dieser Entscheidungsbaum
/// view-privat und ungetestet, nur die Blätter waren gepinnt.
final class PlaybackSourceTests: XCTestCase {

    private let source = URL(fileURLWithPath: "/tmp/meeting.wav")
    private let corrected = URL(fileURLWithPath: "/tmp/meeting-corrected.wav")

    func testMatchingDurationNeedsNoCorrection() {
        let resolved = PlaybackSource.resolve(
            sourceURL: source,
            fileDuration: 600,
            expectedDuration: 600,
            render: { _, _, _ in XCTFail("Ohne Korrektur darf nie gerendert werden"); return nil }
        )
        XCTAssertEqual(resolved, PlaybackSource.Resolved(url: source, rate: 1, corrected: false, displayRate: 1))
    }

    func testCorrectionPrefersRenderedCopyAtRateOne() {
        let resolved = PlaybackSource.resolve(
            sourceURL: source,
            fileDuration: 300,
            expectedDuration: 600,
            render: { _, _, _ in self.corrected }
        )
        XCTAssertEqual(resolved.url, corrected)
        XCTAssertEqual(resolved.rate, 1, "Die Kopie ist bereits zeitkorrigiert — Player läuft normal")
        XCTAssertTrue(resolved.corrected)
        XCTAssertEqual(resolved.displayRate, 0.5, accuracy: 0.001)
    }

    func testRenderUnavailableFallsBackToRateWithFloor() {
        // ratio 0.2 → Korrektur-Rate 0.2, aber der Player-Floor ist 0.5.
        let resolved = PlaybackSource.resolve(
            sourceURL: source,
            fileDuration: 120,
            expectedDuration: 600,
            render: { _, _, _ in nil }
        )
        XCTAssertEqual(resolved.url, source)
        XCTAssertEqual(resolved.rate, PlaybackSource.minFallbackRate)
        XCTAssertTrue(resolved.corrected)
        XCTAssertEqual(resolved.displayRate, 0.2, accuracy: 0.001,
                       "Die Pille zeigt die echte Korrektur-Rate, nicht den Floor")
    }

    func testRenderFailureFallsBackLikeUnavailable() {
        struct RenderError: Error {}
        let resolved = PlaybackSource.resolve(
            sourceURL: source,
            fileDuration: 300,
            expectedDuration: 600,
            render: { _, _, _ in throw RenderError() }
        )
        XCTAssertEqual(resolved.url, source)
        XCTAssertEqual(resolved.rate, 0.5, accuracy: 0.001)
        XCTAssertTrue(resolved.corrected)
    }

    func testLongerFileThanExpectedIsLeftAlone() {
        // PitchGuard korrigiert nur zu KURZE Dateien (ratio < 1).
        let resolved = PlaybackSource.resolve(
            sourceURL: source,
            fileDuration: 900,
            expectedDuration: 600,
            render: { _, _, _ in XCTFail("ratio > 1 darf nie rendern"); return nil }
        )
        XCTAssertFalse(resolved.corrected)
        XCTAssertEqual(resolved.rate, 1)
    }
}
