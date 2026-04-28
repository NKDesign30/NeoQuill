import AVFoundation
import Foundation

struct SilenceDetector {
    let threshold: Float
    let timeoutSeconds: Double

    private var silenceStart: Date?

    init(threshold: Float = 0.01, timeoutSeconds: Double = 3.0) {
        self.threshold = threshold
        self.timeoutSeconds = timeoutSeconds
    }

    mutating func process(buffer: AVAudioPCMBuffer, now: Date = Date()) -> Bool {
        process(rms: calculateRMS(buffer: buffer), now: now)
    }

    mutating func process(rms: Float, now: Date = Date()) -> Bool {
        if rms < threshold {
            if let startedAt = silenceStart {
                return now.timeIntervalSince(startedAt) > timeoutSeconds
            }
            silenceStart = now
            return false
        }

        silenceStart = nil
        return false
    }

    mutating func reset() {
        silenceStart = nil
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        return sqrt(sum / Float(frameLength))
    }
}
