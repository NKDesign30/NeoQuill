import SwiftUI

// Footer-FAB: 28x28 rund, Mic im Idle-State, Stop wenn Recording. Tight border, kein Glow.

struct NewRecordingButton: View {
    let recording: Bool
    var accent: Color = Neon.brandPrimary
    var action: () -> Void = {}

    @State private var hovering = false

    private var bg: Color { recording ? Neon.recordingDot : accent }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(hovering ? bg : bg.opacity(0.86))
                .frame(width: 28, height: 28)
                .overlay(
                    GlyphView(name: recording ? .stop : .mic, size: 13, weight: .semibold, color: .white)
                )
                .overlay(
                    Circle().stroke(bg.opacity(0.4), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Neon.Duration.fast), value: hovering)
    }
}
