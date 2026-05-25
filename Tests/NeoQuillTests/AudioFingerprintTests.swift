import XCTest
@testable import NeoQuill

final class AudioFingerprintTests: XCTestCase {
    func testSHA256IsStableForSameSamplesAndChangesWhenSamplesChange() {
        let first = AudioFingerprint.sha256(samples: [0, 0.25, -0.5])
        let second = AudioFingerprint.sha256(samples: [0, 0.25, -0.5])
        let changed = AudioFingerprint.sha256(samples: [0, 0.25, -0.25])

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, changed)
        XCTAssertEqual(first.count, 64)
    }
}
