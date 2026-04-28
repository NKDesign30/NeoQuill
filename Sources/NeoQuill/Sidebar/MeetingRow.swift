import SwiftUI

// Eine Meeting-Zeile in der Sidebar.
// Active: weiß-Tint + bold Title + emerald-MicGlyph (KEINE Left-Border, KEIN green-bg-Glow!).

struct MeetingRow: View {

    let meeting: MeetingSummary
    let active: Bool
    let isRecording: Bool
    let density: SidebarDensity
    var accent: Color = Neon.brandPrimary
    var onTap: () -> Void

    @State private var hovering = false

    private var padY: CGFloat {
        switch density {
        case .compact: return 7
        case .regular: return 9
        case .comfy:   return 11
        }
    }

    private var background: Color {
        if active { return accent.opacity(0.08) }
        if hovering { return Color.white.opacity(0.04) }
        return .clear
    }

    private var titleColor: Color {
        active ? Neon.textPrimary : Neon.textSecondary
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                MicGlyph(active: active, recording: isRecording, accent: accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(meeting.title)
                            .font(.neonBody(13, weight: active ? .semibold : .regular))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if meeting.unread {
                            Circle()
                                .fill(accent)
                                .frame(width: 5, height: 5)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("\(meeting.date), \(meeting.time)")
                            .font(.neonMono(10))
                            .foregroundStyle(Neon.textTertiary)
                        Text("·").foregroundStyle(Neon.textQuaternary).font(.neonMono(10))
                        Text(meeting.duration)
                            .font(.neonMono(10))
                            .foregroundStyle(Neon.textTertiary)
                        Text("·").foregroundStyle(Neon.textQuaternary).font(.neonMono(10))
                        PlatformBadge(platform: meeting.platform)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isRecording {
                    Text("● REC")
                        .font(.neonMono(9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Neon.recordingDotBright)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, padY)
            .background(
                RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Neon.Duration.fast), value: hovering)
        .animation(.easeOut(duration: Neon.Duration.fast), value: active)
    }
}
