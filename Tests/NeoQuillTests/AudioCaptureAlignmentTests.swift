import XCTest
@testable import NeoQuill

/// Guards the time-alignment of the HQ stereo stems. The mic and system sources
/// start at different times (mic often falls back to AVAudioEngine a few seconds
/// in); without front-padding the later stem would play time-shifted.
final class AudioCaptureAlignmentTests: XCTestCase {
    func testNoOffsetLeavesSamplesUnchanged() {
        let s: [Float] = [0.1, 0.2, 0.3]
        XCTAssertEqual(AudioCapture.frontPadded(s, offset: nil, sampleRate: 48_000), s)
        XCTAssertEqual(AudioCapture.frontPadded(s, offset: 0, sampleRate: 48_000), s)
    }

    func testTinyOffsetBelowThresholdIgnored() {
        let s: [Float] = [0.5, 0.5]
        // < 10 ms is treated as noise, not a real start delay.
        XCTAssertEqual(AudioCapture.frontPadded(s, offset: 0.005, sampleRate: 48_000), s)
    }

    func testFourSecondOffsetFrontPadsExactSilence() {
        let s: [Float] = Array(repeating: 0.3, count: 1_000)
        let out = AudioCapture.frontPadded(s, offset: 4.0, sampleRate: 48_000)
        let expectedPad = 4 * 48_000
        XCTAssertEqual(out.count, expectedPad + s.count)
        XCTAssertEqual(Array(out.prefix(expectedPad)), [Float](repeating: 0, count: expectedPad))
        XCTAssertEqual(Array(out.suffix(s.count)), s)
    }

    func testRelativeAlignmentBetweenStems() {
        // System starts ~immediately, mic ~4s late. After padding both share the
        // same timeline length and the mic content begins 4s in.
        let mic = Array(repeating: Float(0.4), count: 48_000)   // 1s of mic
        let sys = Array(repeating: Float(0.6), count: 48_000 * 5) // 5s of system
        let micA = AudioCapture.frontPadded(mic, offset: 4.0, sampleRate: 48_000)
        let sysA = AudioCapture.frontPadded(sys, offset: 0.05, sampleRate: 48_000)
        // mic now sits at 4s..5s, system at ~0s..5s — both end around 5s.
        XCTAssertEqual(micA.count, 48_000 * 5)
        XCTAssertEqual(sysA.count, 48_000 * 5 + Int(0.05 * 48_000))
        XCTAssertEqual(Array(micA.prefix(48_000 * 4)), [Float](repeating: 0, count: 48_000 * 4))
        XCTAssertEqual(micA[48_000 * 4], 0.4)  // mic audio begins exactly at 4s
    }

    func testAbsurdOffsetIsCapped() {
        let s: [Float] = [0.1]
        let out = AudioCapture.frontPadded(s, offset: 99_999, sampleRate: 48_000)
        XCTAssertLessThanOrEqual(out.count, 48_000 * 600 + 1)  // capped at 10 min
    }

    // MARK: - alignedMix (mono mix is front-padded just like the HQ archive)

    func testAlignedMixPadsLateMicOntoSystemTimeline() {
        // System starts immediately, mic 2s late (AVAudioEngine fallback). At 16k
        // the mic content must begin at 2s, not at index 0 over the system audio.
        let mic = Array(repeating: Float(0.4), count: 16_000)       // 1s mic
        let sys = Array(repeating: Float(0.5), count: 16_000 * 3)   // 3s system
        let mixed = AudioCapture.alignedMix(
            mic: mic, micOffset: 2.0,
            system: sys, systemOffset: 0.0,
            sampleRate: 16_000
        )
        XCTAssertEqual(mixed.count, 16_000 * 3)            // system defines the length
        XCTAssertEqual(mixed[0], 0.5, accuracy: 1e-6)      // first 2s: system only
        XCTAssertEqual(mixed[16_000], 0.5, accuracy: 1e-6) // still system-only at 1s
        XCTAssertEqual(mixed[16_000 * 2], 0.9, accuracy: 1e-6) // mic joins at 2s (0.4+0.5)
    }

    func testAlignedMixWithoutOffsetsMatchesNaiveSum() {
        // No offsets (legacy/mic-only) → behaves like the old index-0 mix.
        let mic: [Float] = [0.2, 0.2, 0.2]
        let sys: [Float] = [0.1, 0.1]
        let mixed = AudioCapture.alignedMix(
            mic: mic, micOffset: nil,
            system: sys, systemOffset: nil,
            sampleRate: 16_000
        )
        XCTAssertEqual(mixed.count, 3)
        XCTAssertEqual(mixed[0], 0.3, accuracy: 1e-6)
        XCTAssertEqual(mixed[1], 0.3, accuracy: 1e-6)
        XCTAssertEqual(mixed[2], 0.2, accuracy: 1e-6)
    }

    func testAlignedMixClipsPeaks() {
        let mic: [Float] = [0.8, 0.8]
        let sys: [Float] = [0.8, 0.8]
        let mixed = AudioCapture.alignedMix(
            mic: mic, micOffset: nil,
            system: sys, systemOffset: nil,
            sampleRate: 16_000
        )
        XCTAssertEqual(mixed, [0.95, 0.95])  // 1.6 hard-clipped to 0.95
    }

    func testAlignedMixEmptyInputs() {
        XCTAssertTrue(AudioCapture.alignedMix(
            mic: [], micOffset: nil, system: [], systemOffset: nil, sampleRate: 16_000
        ).isEmpty)
    }
}
