import AVFoundation
import XCTest
@testable import NeoQuill

/// Proves the streaming converter does not drop frames the way the old
/// single-shot/`reset()`-per-buffer paths did — the root cause of the high-pitch
/// playback bug.
final class PCMStreamConverterTests: XCTestCase {
    private func buffer(sampleRate: Double, frames: Int, value: Float = 0.1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        )!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        if let ch = buf.floatChannelData?[0] {
            for i in 0..<frames { ch[i] = value }
        }
        return buf
    }

    /// Mirrors the real Core Audio process tap: 48 kHz, 2 channels, interleaved,
    /// tiny callbacks (~154 frames). A sine fill keeps the resampler honest (a DC
    /// fill can hide filter behaviour).
    private func tapStyleBuffer(frames: Int, phase: inout Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true
        )!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buf.frameLength = AVAudioFrameCount(frames)
        // Interleaved stereo lives in the first audioBufferList buffer as L,R,L,R…
        let abl = buf.mutableAudioBufferList
        let ptr = abl.pointee.mBuffers.mData!.assumingMemoryBound(to: Float.self)
        let inc = 2.0 * Double.pi * 240.0 / 48_000.0   // ~240 Hz, speech-ish
        for i in 0..<frames {
            let s = Float(sin(phase))
            ptr[i * 2] = s
            ptr[i * 2 + 1] = s
            phase += inc
        }
        return buf
    }

    func testIdentityConversionPreservesFrameCount() throws {
        // 48 kHz -> 48 kHz (the common case when the tap is already 48 kHz):
        // must be frame-exact, otherwise the archive drifts shorter than wall-clock.
        let conv = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 48_000))
        let out = try XCTUnwrap(conv.convert(buffer(sampleRate: 48_000, frames: 1_024)))
        XCTAssertEqual(out.count, 1_024)
    }

    func testDownsampleAccumulatesExpectedFramesAcrossManyBuffers() throws {
        // 48 kHz -> 16 kHz over 200 buffers: total output must track input/3 closely.
        // The old truncating path lost the fractional frame every callback; this
        // one must stay within a tight tolerance of the ideal ratio.
        let conv = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 16_000))
        var totalOut = 0
        let buffersCount = 200
        let inFrames = 1_024
        for _ in 0..<buffersCount {
            if let out = conv.convert(buffer(sampleRate: 48_000, frames: inFrames)) {
                totalOut += out.count
            }
        }
        let expected = Double(buffersCount * inFrames) / 3.0
        XCTAssertEqual(Double(totalOut), expected, accuracy: expected * 0.01)
    }

    /// THE regression test for the real bug: the Core Audio tap delivers tiny
    /// ~154-frame stereo 48 kHz callbacks. The old reset()-per-buffer + floor()
    /// path lost ~half the frames at this size/ratio → 2.06x time-compression
    /// ("fast-forwarded, high-pitched" remote voices). The drain-correct
    /// converter must keep total output at input/3 within a tiny fixed slack for
    /// the one-time resampler priming latency — NOT a per-buffer percentage.
    func testTinyTapBuffersDoNotTimeCompress() throws {
        let conv = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 16_000))
        var phase = 0.0
        var totalIn = 0
        var totalOut = 0
        // ~12s of audio in 154-frame chunks: enough to expose accumulating drift.
        for _ in 0..<3_900 {
            let buf = tapStyleBuffer(frames: 154, phase: &phase)
            totalIn += 154
            if let out = conv.convert(buf) { totalOut += out.count }
        }
        let expected = Double(totalIn) / 3.0
        // Slack = a few resampler windows, absolute, not proportional. The broken
        // path would land near expected/2 (~50% loss) — orders of magnitude out.
        XCTAssertEqual(Double(totalOut), expected, accuracy: 512,
                       "tiny-buffer downsample must not lose frames (broken path ≈ \(Int(expected/2)))")
    }

    /// Real taps deliver variable tiny frame counts (154, 160, 165…), not a fixed
    /// size. Variable small buffers must not accumulate time-compression either.
    func testVariableTinyBuffersStayLengthAccurate() throws {
        let conv = try XCTUnwrap(PCMStreamConverter(targetSampleRate: 16_000))
        var phase = 0.0
        let sizes = [154, 160, 148, 165, 152]
        var totalIn = 0
        var totalOut = 0
        for i in 0..<3_000 {
            let frames = sizes[i % sizes.count]
            let buf = tapStyleBuffer(frames: frames, phase: &phase)
            totalIn += frames
            if let out = conv.convert(buf) { totalOut += out.count }
        }
        let expected = Double(totalIn) / 3.0
        XCTAssertEqual(Double(totalOut), expected, accuracy: 512)
    }
}
