import SwiftUI

// Display-Title + Platform-Badge + Stat-Row + ParticipantStack.

struct HeaderHero: View {
    let meeting: MeetingDetail
    var accent: Color = Neon.brandPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                platformPill
                Text("\(meeting.dateLong) · \(meeting.timeRange)")
                    .neonEyebrow()
            }
            .padding(.bottom, 14)

            Text(meeting.title)
                .font(.neonDisplay(40))
                .foregroundStyle(Neon.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Neon.strokeHairline)
                .frame(height: Neon.hairlineWidth)
                .padding(.top, 22)
                .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 28) {
                Stat(label: "Dauer",         value: meeting.duration, mono: true)
                Stat(label: "Wörter",        value: formatted(meeting.wordCount))
                Stat(label: "Teilnehmer",    value: "\(meeting.participantCount)")
                Stat(label: "Aktionspunkte", value: "\(meeting.openTasks)", accent: accent)
                Spacer(minLength: 16)
                ParticipantStack(participants: meeting.participants)
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 36)
        .padding(.bottom, 20)
    }

    private var platformPill: some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text("MEETING · \(meeting.platform.rawValue)")
                .font(.neonMono(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(accent.opacity(0.10)))
    }

    private func formatted(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var mono: Bool = false
    var accent: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).neonEyebrow()
            Text(value)
                .font(mono ? .neonMonoStat : .neonDisplay(22))
                .foregroundStyle(accent ?? Neon.textPrimary)
                .monospacedDigit()
        }
    }
}
