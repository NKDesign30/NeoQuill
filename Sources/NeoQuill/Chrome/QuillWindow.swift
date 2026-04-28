import SwiftUI

// Warm-dark macOS-Window-Frame: Backdrop-Padding, abgerundeter Innen-Frame, Title-Bar
// mit Traffic-Lights und mittigem App-Titel. Inhalt = Sidebar + Detail-Container.

struct QuillWindow<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            Neon.windowBackdrop.ignoresSafeArea()
            VStack(spacing: 0) {
                titleBar
                Divider().background(Neon.strokeHairline)
                HStack(spacing: 0) {
                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Neon.surfaceBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 30)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                trafficLight(Neon.recordingDot)
                trafficLight(Neon.statusWarning)
                trafficLight(Neon.brandPrimary)
                Spacer()
            }
            Text("NeoQuill")
                .font(.neonBody(12, weight: .medium))
                .foregroundStyle(Neon.textTertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.03), .clear],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 12, height: 12)
    }
}
