import SwiftUI

// Sticky-Header pro Datums-Gruppe: Mono-Eyebrow auf Sidebar-Background.

struct GroupHeader: View {
    let label: String

    var body: some View {
        Text(label)
            .neonEyebrow(Neon.textTertiary)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Neon.surfaceBackground.opacity(0.96), Neon.surfaceBackground.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
    }
}
