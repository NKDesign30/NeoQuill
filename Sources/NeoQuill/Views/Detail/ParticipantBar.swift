import SwiftUI

// Sprechanteil-Bar pro Teilnehmer: Avatar | Name+Role+spoke%/time | Bar.

struct ParticipantBar: View {
    let participant: Participant
    let totalSeconds: Int
    var accent: Color = Neon.brandPrimary

    private var spokeSeconds: Int { Self.parseSpoke(participant.spoke) }
    private var percent: Int {
        guard totalSeconds > 0 else { return 0 }
        return Int((Double(spokeSeconds) / Double(totalSeconds)) * 100.0)
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(initials: participant.id, color: participant.color, size: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(participant.name)
                        .font(.neonBody(13, weight: .medium))
                        .foregroundStyle(Neon.textPrimary)
                    Text(participant.role)
                        .font(.neonBody(12))
                        .foregroundStyle(Neon.textTertiary)
                    Spacer(minLength: 8)
                    Text("\(participant.spoke) · \(percent)%")
                        .font(.neonMono(11))
                        .foregroundStyle(Neon.textTertiary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    let w = max(0, geo.size.width * Double(percent) / 100)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule().fill(participant.color).frame(width: w)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    static func parseSpoke(_ s: String) -> Int {
        // "11m 47s" → 707
        let cleaned = s.replacingOccurrences(of: "s", with: "")
        let parts = cleaned.split(separator: "m").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2,
              let m = Int(parts[0]),
              let sec = Int(parts[1])
        else { return 0 }
        return m * 60 + sec
    }
}
