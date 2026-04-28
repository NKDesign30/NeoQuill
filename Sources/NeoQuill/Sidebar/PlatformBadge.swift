import SwiftUI

// Mono Badge "TEAMS / ZOOM / MEET / CALL" — Speaker-Color zur Differenzierung.

struct PlatformBadge: View {
    let platform: Platform

    var body: some View {
        Text(platform.rawValue)
            .font(.neonMono(9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(platform.accent)
    }
}
