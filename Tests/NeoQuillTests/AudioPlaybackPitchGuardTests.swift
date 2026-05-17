import XCTest
@testable import NeoQuill

final class AudioPlaybackPitchGuardTests: XCTestCase {
    func testKeepsNormalRateWhenDurationsMatch() {
        let decision = AudioPlaybackPitchGuard.decide(fileDuration: 600, expectedDuration: 610)

        XCTAssertEqual(decision.rate, 1)
        XCTAssertFalse(decision.corrected)
    }

    func testSlowsDownHighPitchedShortFile() {
        let decision = AudioPlaybackPitchGuard.decide(fileDuration: 300, expectedDuration: 600)

        XCTAssertEqual(decision.rate, 0.5)
        XCTAssertTrue(decision.corrected)
        XCTAssertEqual(decision.reason, "file shorter than meeting")
    }

    func testSpeedsUpLongFile() {
        let decision = AudioPlaybackPitchGuard.decide(fileDuration: 900, expectedDuration: 600)

        XCTAssertEqual(decision.rate, 1.5)
        XCTAssertTrue(decision.corrected)
        XCTAssertEqual(decision.reason, "file longer than meeting")
    }

    func testIgnoresInvalidDurations() {
        let decision = AudioPlaybackPitchGuard.decide(fileDuration: 0, expectedDuration: 600)

        XCTAssertEqual(decision.rate, 1)
        XCTAssertFalse(decision.corrected)
    }
}
