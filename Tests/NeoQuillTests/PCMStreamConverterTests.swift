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
}
