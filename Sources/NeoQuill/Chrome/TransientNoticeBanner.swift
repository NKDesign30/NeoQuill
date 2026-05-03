import SwiftUI

// Schwebender Hinweis am oberen Rand. Zeigt Backfill-Resultate, kurze Status-
// Meldungen und Änderungen die sonst stillschweigend passieren würden.

struct TransientNoticeBanner: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let message = state.transientNotice {
            HStack(spacing: 10) {
                Circle()
                    .fill(Neon.brandPrimary)
                    .frame(width: 8, height: 8)
                Text(message)
                    .font(.neonBody(12, weight: .medium))
                    .foregroundStyle(Neon.textPrimary)
                Button {
                    state.dismissNotice()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Neon.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Neon.brandPrimary.opacity(0.4), lineWidth: Neon.hairlineWidth)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 12)
        }
    }
}
