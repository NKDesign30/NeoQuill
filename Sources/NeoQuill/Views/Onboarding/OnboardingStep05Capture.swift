import SwiftUI

// 05 — Quellen. 5 Toggle-Rows (Teams/Zoom/Meet/System/Lokal).
// Visual: Mock-Kalender, dimmt Termine deren Plattform deaktiviert ist.

struct CaptureContent: View {
    @ObservedObject var state: OnboardingState
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingHeading(
                title: "Was soll Quill aufnehmen?",
                lead: "Wähle, welche Plattformen Quill automatisch erfassen soll. Du kannst das später jederzeit pro Meeting überschreiben.",
                accent: accent
            )

            VStack(alignment: .leading, spacing: 8) {
                OnboardingToggleRow(symbol: "person.2.fill", title: "Microsoft Teams",
                                    subtitle: "Erkennt Anrufe automatisch · Calendar-Integration",
                                    badge: "TEAMS",
                                    value: $state.captureTeams, accent: accent)
                OnboardingToggleRow(symbol: "person.2.fill", title: "Zoom",
                                    subtitle: "Hookt sich in den Zoom-Audio-Stream ein",
                                    badge: "ZOOM",
                                    value: $state.captureZoom, accent: accent)
                OnboardingToggleRow(symbol: "person.2.fill", title: "Google Meet",
                                    subtitle: "Browser-Tab-Audio über System-Capture",
                                    badge: "MEET",
                                    value: $state.captureMeet, accent: accent)
                OnboardingToggleRow(symbol: "waveform", title: "System-Audio",
                                    subtitle: "Alles was dein Mac abspielt — Calls, YouTube, …",
                                    value: $state.captureSystem, accent: accent)
                OnboardingToggleRow(symbol: "mic", title: "Lokale Aufnahmen",
                                    subtitle: "Manuelle Aufnahmen über ⌥+R oder die Menüleiste",
                                    value: $state.captureLocal, accent: accent)
            }
            .frame(maxWidth: 460)
        }
    }
}

struct CaptureVisual: View {
    @ObservedObject var state: OnboardingState
    let accent: Color

    private var items: [(time: String, title: String, platform: String, key: SourceKey, duration: String)] {
        [
            ("09:30", "Daily Standup",              "TEAMS", .teams, "15m"),
            ("11:00", "AM Solutions — Q2 Roadmap",  "ZOOM",  .zoom,  "32m"),
            ("14:00", "1:1 mit Sarah",              "MEET",  .meet,  "30m"),
            ("15:30", "NK Voice Memo",              "CALL",  .local, "8m"),
        ]
    }

    enum SourceKey { case teams, zoom, meet, system, local }

    private func isOn(_ key: SourceKey) -> Bool {
        switch key {
        case .teams:  return state.captureTeams
        case .zoom:   return state.captureZoom
        case .meet:   return state.captureMeet
        case .system: return state.captureSystem
        case .local:  return state.captureLocal
        }
    }

    private var activeCount: Int {
        [state.captureTeams, state.captureZoom, state.captureMeet,
         state.captureSystem, state.captureLocal].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HEUTE · SAMSTAG")
                        .font(.neonMono(9))
                        .tracking(1.0)
                        .foregroundStyle(Neon.textTertiary)
                    Text("3. Mai")
                        .font(.neonDisplay(24))
                        .foregroundStyle(Neon.textPrimary)
                }
                Spacer()
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(Neon.textTertiary)
            }

            VStack(spacing: 6) {
                ForEach(items, id: \.time) { item in
                    calendarRow(item)
                }
            }

            Divider().background(Neon.strokeHairline)

            HStack {
                Text("\(activeCount) VON 5 QUELLEN AKTIV")
                    .font(.neonMono(10))
                    .tracking(0.6)
                    .foregroundStyle(Neon.textTertiary)
                Spacer()
                Text("● BEREIT")
                    .font(.neonMono(10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(accent)
            }
        }
        .padding(20)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: 0x242422).opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
    }

    private func calendarRow(_ item: (time: String, title: String, platform: String, key: SourceKey, duration: String)) -> some View {
        let on = isOn(item.key)
        return HStack(spacing: 10) {
            Text(item.time)
                .font(.neonMono(11))
                .foregroundStyle(Neon.textTertiary)
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.platform)
                        .font(.neonMono(9))
                        .tracking(0.6)
                        .foregroundStyle(on ? accent : Neon.textTertiary.opacity(0.6))
                    Text("·")
                        .foregroundStyle(Neon.textTertiary.opacity(0.4))
                    Text(item.duration)
                        .font(.neonMono(9))
                        .tracking(0.6)
                        .foregroundStyle(on ? accent : Neon.textTertiary.opacity(0.6))
                }
            }
            Spacer()
            recordingDot(on: on)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(on ? accent.opacity(0.06) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(on ? accent.opacity(0.2) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
        .opacity(on ? 1 : 0.5)
    }

    private func recordingDot(on: Bool) -> some View {
        Group {
            if on {
                ZStack {
                    Circle().fill(accent)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
            } else {
                Circle()
                    .strokeBorder(Neon.strokeDefault, style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .frame(width: 18, height: 18)
            }
        }
    }
}
