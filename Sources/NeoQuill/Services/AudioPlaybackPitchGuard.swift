import Foundation

enum AudioPlaybackPitchGuard {
    struct Decision: Equatable {
        let rate: Float
        let corrected: Bool
        let reason: String?
    }

    static func decide(
        fileDuration: TimeInterval,
        expectedDuration: TimeInterval,
        tolerance: Double = 0.12
    ) -> Decision {
        guard fileDuration.isFinite,
              expectedDuration.isFinite,
              fileDuration > 0,
              expectedDuration > 0 else {
            return Decision(rate: 1, corrected: false, reason: nil)
        }

        let ratio = fileDuration / expectedDuration
        guard abs(1 - ratio) > tolerance else {
            return Decision(rate: 1, corrected: false, reason: nil)
        }

        guard ratio < 1 else {
            return Decision(rate: 1, corrected: false, reason: nil)
        }

        let clamped = max(ratio, 0.5)
        let reason = "file shorter than meeting"
        return Decision(rate: Float(clamped), corrected: true, reason: reason)
    }
}
