import AVFoundation

/// Streaming sample-rate converter with correct drain behaviour.
///
/// The legacy capture paths called `converter.reset()` on every input buffer and
/// sized the output to `floor(frames * ratio)` with no slack. That discarded the
/// resampler filter tail and the fractional frame on each callback, so the
/// recording came out slightly short — which accumulates over a long meeting and
/// shows up as too-high pitch on playback.
///
/// This class keeps ONE converter per stream (the resampler state survives across
/// calls, no per-buffer `reset()`) and gives the converter enough output capacity
/// including headroom. It is used for the high-resolution 48 kHz archive path; the
/// existing 16 kHz ASR path is left untouched.
final class PCMStreamConverter {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    init?(targetSampleRate: Double, channels: AVAudioChannelCount = 1) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: channels,
            interleaved: false
        ) else { return nil }
        self.targetFormat = format
    }

    /// Converts a native PCM buffer into the target format and returns channel 0's
    /// samples. The converter is reused across calls; it is only rebuilt when the
    /// source format changes.
    func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }

        if converter == nil || sourceFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        // Round up plus fixed headroom so the filter tail and partial frames have
        // room and are not dropped.
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 4096
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return nil }

        // Feed this one buffer exactly once, then `.noDataNow` so the converter
        // keeps its internal state for the next call (not `.endOfStream` — the
        // stream continues).
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil,
              let channel = output.floatChannelData?[0],
              output.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}
