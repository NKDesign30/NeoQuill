import SwiftUI

// 56px Orb für aktive Aufnahme: pulsierender Außenring + halbtransparenter Mantel + Kern.

struct LiveOrb: View {

    var color: Color = Neon.recordingDot

    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 2)
                .scaleEffect(animate ? 1.6 : 1.0)
                .opacity(animate ? 0 : 0.7)
                .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: animate)

            Circle()
                .fill(color.opacity(0.2))
                .padding(8)

            Circle()
                .fill(color)
                .padding(16)
                .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 0)
        }
        .frame(width: 56, height: 56)
        .onAppear { animate = true }
    }
}
