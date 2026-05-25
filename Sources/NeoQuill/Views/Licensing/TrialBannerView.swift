import SwiftUI

/// Dezenter Banner über dem Detail-Layout während Trial / nach Ablauf /
/// bei ungültiger Lizenz. Click öffnet das `LicenseGateSheet`.
struct TrialBannerView: View {

    let snapshot: LicenseSnapshot
    let onTap: () -> Void

    var body: some View {
        if let content = Self.bannerContent(for: snapshot) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: content.symbol)
                        .foregroundStyle(content.tint)
                    Text(content.headline).bold()
                    Text("·").foregroundStyle(.secondary)
                    Text(content.sub).foregroundStyle(.secondary)
                    Spacer()
                    Text(content.cta)
                        .foregroundStyle(content.tint)
                        .bold()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(content.tint.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(content.tint.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    struct BannerContent: Equatable {
        let symbol: String
        let tint: Color
        let headline: String
        let sub: String
        let cta: String
    }

    /// Pure-Logik für Tests: aus dem Snapshot wird der Banner-Content abgeleitet
    /// oder `nil` wenn kein Banner gezeigt werden soll.
    static func bannerContent(for snapshot: LicenseSnapshot) -> BannerContent? {
        switch snapshot.status {
        case .trial(let days):
            return BannerContent(
                symbol: "hourglass",
                tint: .orange,
                headline: "Trial läuft",
                sub: "Noch \(days) Tag\(days == 1 ? "" : "e") für Pro-Features",
                cta: "Lizenz holen"
            )
        case .trialExpired:
            return BannerContent(
                symbol: "hourglass.bottomhalf.filled",
                tint: .red,
                headline: "Trial abgelaufen",
                sub: "Pro-Features sind deaktiviert",
                cta: "Lizenz holen"
            )
        case .invalidated:
            return BannerContent(
                symbol: "exclamationmark.triangle.fill",
                tint: .red,
                headline: "Lizenz ungültig",
                sub: "Bitte erneut aktivieren",
                cta: "Aktivieren"
            )
        case .notRequired, .betaGrace, .activated:
            return nil
        }
    }
}
