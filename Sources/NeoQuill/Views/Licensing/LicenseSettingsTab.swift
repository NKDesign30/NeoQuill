import SwiftUI

/// Settings-Tab "Lizenz". Zeigt aktuellen Status und bietet Aktionen je nach Phase:
///
///   - `.notRequired`  → freundliche Beta-Notice, keine Aktionen
///   - `.betaGrace`    → "Lifelong free, danke" + License-Key (falls vorhanden)
///   - `.trial`        → Countdown + Buy/Activate
///   - `.trialExpired` → Buy/Activate prominent
///   - `.activated`    → Tier + Deactivate
///   - `.invalidated`  → Begründung + Buy/Activate
struct LicenseSettingsTab: View {

    @EnvironmentObject private var state: AppState
    @State private var showGate = false

    var body: some View {
        Form {
            statusSection
            actionSection
            metadataSection
        }
        .padding()
        .sheet(isPresented: $showGate) {
            LicenseGateSheet()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusHeadline).font(.headline)
                    Text(statusSubline).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                modeBadge
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        let snapshot = state.license.snapshot
        switch snapshot.status {
        case .notRequired:
            EmptyView()

        case .betaGrace:
            EmptyView()

        case .trial:
            Section("Aktionen") {
                Button("Lizenz kaufen oder aktivieren") { showGate = true }
                    .buttonStyle(.borderedProminent)
            }

        case .trialExpired, .invalidated:
            Section("Aktionen") {
                Button("Lizenz kaufen oder aktivieren") { showGate = true }
                    .buttonStyle(.borderedProminent)
                Text("Pro-Features (Summary, Speaker-ID, Imports) sind ohne aktive Lizenz deaktiviert. Recording und lokales Transkript bleiben frei.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .activated:
            Section("Aktionen") {
                Button("Lizenz auf diesem Gerät deaktivieren") {
                    Task { await state.license.deactivate() }
                }
                .buttonStyle(.bordered)
                .help("Gibt einen Aktivierungs-Slot frei, damit du die Lizenz auf einem anderen Mac aktivieren kannst.")
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        let snapshot = state.license.snapshot
        Section("Details") {
            if let activation = snapshot.activation {
                LabeledContent("Lizenz") {
                    Text(activation.licenseKey)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Tier") { Text(activation.tier.displayName) }
                LabeledContent("Aktiviert seit") {
                    Text(activation.activatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Zuletzt validiert") {
                    Text(activation.lastValidatedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if let firstLaunch = snapshot.firstLaunchDate {
                LabeledContent("Erster Start") {
                    Text(firstLaunch.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Status-Anzeige

    private var statusIcon: some View {
        let snapshot = state.license.snapshot
        let symbol: String
        let color: Color
        switch snapshot.status {
        case .notRequired:        symbol = "leaf.fill";          color = .gray
        case .betaGrace:          symbol = "heart.fill";         color = .pink
        case .trial:              symbol = "hourglass";          color = .orange
        case .trialExpired:       symbol = "hourglass.bottomhalf.filled"; color = .red
        case .activated:          symbol = "checkmark.seal.fill"; color = .green
        case .invalidated:        symbol = "exclamationmark.triangle.fill"; color = .red
        }
        return Image(systemName: symbol).foregroundStyle(color).font(.title2).frame(width: 28)
    }

    private var statusHeadline: String {
        switch state.license.snapshot.status {
        case .notRequired:                          return "Beta-Phase aktiv"
        case .betaGrace:                            return "Beta Lifetime — danke fürs Testen!"
        case .trial(let d):                         return "Trial läuft — noch \(d) Tag\(d == 1 ? "" : "e")"
        case .trialExpired:                         return "Trial abgelaufen"
        case .activated(let tier, _):               return "Aktiviert: \(tier.displayName)"
        case .invalidated(let reason):              return "Lizenz ungültig (\(invalidationLabel(reason)))"
        }
    }

    private var statusSubline: String {
        switch state.license.snapshot.status {
        case .notRequired:
            return "Alle Features kostenlos nutzbar bis NeoQuill den Verkauf eröffnet."
        case .betaGrace:
            return "Du hattest die App vor dem Stichtag installiert — alle Pro-Features bleiben lebenslang frei."
        case .trial:
            return "Pro-Features verfügbar. Danach kannst du eine Lizenz kaufen."
        case .trialExpired:
            return "Recording und Transkript funktionieren weiter. Pro-Features brauchen eine Lizenz."
        case .activated:
            return "Alle Pro-Features freigeschaltet."
        case .invalidated:
            return "Deine Lizenz wurde zurückgezogen oder konnte nicht mehr validiert werden."
        }
    }

    private var modeBadge: some View {
        let label: String = state.license.snapshot.mode == .disabled ? "Beta" : "Lizenz aktiv"
        let bg: Color = state.license.snapshot.mode == .disabled ? .gray.opacity(0.2) : .green.opacity(0.15)
        return Text(label)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg, in: Capsule())
    }

    private func invalidationLabel(_ reason: InvalidationReason) -> String {
        switch reason {
        case .refunded:                return "erstattet"
        case .revokedByOwner:          return "deaktiviert"
        case .activationLimitExceeded: return "zu viele Geräte"
        case .keyNotFound:             return "Schlüssel unbekannt"
        case .other:                   return "unbekannt"
        }
    }
}
