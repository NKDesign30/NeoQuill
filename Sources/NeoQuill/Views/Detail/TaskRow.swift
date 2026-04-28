import SwiftUI

// Eine Aktionspunkt-Zeile. Toggle-Circle links, Task + Mono-Meta, Avatar rechts.
// Done: Strikethrough + Tertiary, Circle gefüllt.

struct TaskRow: View {

    let task: ActionItem
    let participants: [Participant]
    var accent: Color = Neon.brandPrimary
    var isLast: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(task.status == .done ? accent : Neon.strokeDefault, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if task.status == .done {
                        Circle().fill(accent).frame(width: 18, height: 18)
                        GlyphView(name: .check, size: 11, weight: .bold, color: .white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.task)
                    .font(.neonBody(14))
                    .foregroundStyle(task.status == .done ? Neon.textTertiary : Neon.textPrimary)
                    .strikethrough(task.status == .done, color: Neon.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(participantName(for: task.who).uppercased())
                        .font(.neonMono(10))
                        .tracking(0.4)
                        .foregroundStyle(Neon.textTertiary)
                    Text("·").font(.neonMono(10)).foregroundStyle(Neon.textQuaternary)
                    Text("FÄLLIG \(task.due.uppercased())")
                        .font(.neonMono(10))
                        .tracking(0.4)
                        .foregroundStyle(Neon.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let p = participants.first(where: { $0.id == task.who }) {
                Avatar(initials: p.id, color: p.color, size: 26)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
            }
        }
    }

    private func participantName(for id: String) -> String {
        participants.first(where: { $0.id == id })?.name ?? id
    }
}
