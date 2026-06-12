import SwiftUI

// 06 — Startklar. Hotkey-Picker + Bestätigungs-Card + Signature.
// Visual: Floating Recording-Pill Preview + großer Hotkey-Display + Stats.

struct ReadyContent: View {
    @ObservedObject var state: OnboardingState
    @EnvironmentObject private var appState: AppState
    let accent: Color
    @State private var preparationStatus: RuntimePreparationStatus = .idle

    private var firstName: String? {
        state.name.split(separator: " ").first.map(String.init)
    }

    private var readyTitle: String {
        if let firstName, !firstName.isEmpty {
            return "Bereit, \(firstName)."
        }
        return "Startklar."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            OnboardingHeading(
                title: readyTitle,
                lead: "Eine letzte Sache: dein Aufnahme-Shortcut. Quill bereitet im Hintergrund die lokale Speech-Runtime vor, damit die erste Aufnahme nicht am Modell-Download hängt.",
                accent: accent
            )

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    OnboardingFormLabel(text: "GLOBALER AUFNAHME-SHORTCUT", hint: "· Klick zum Wählen")
                    HotkeyPickerView(parts: $state.hotkeyParts, accent: accent)
                }

                successCard
                runtimePreparationCard
                signatureLine
            }
            .frame(maxWidth: 460)
        }
        .task {
            await prepareRuntimeIfNeeded()
        }
    }

    private var successCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(0.18))
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text("Du bist startklar.")
                    .font(.neonBody(13, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
                Text("Quill nimmt deine Meetings ab jetzt automatisch auf. Die erste Aufnahme erscheint direkt in der Mediathek — mit TL;DR, Aktionspunkten und Kapiteln.")
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.25), lineWidth: Neon.hairlineWidth)
        )
    }

    private var signatureLine: some View {
        HStack(spacing: 8) {
            Text("WAS GESAGT WURDE.")
                .font(.neonMono(10))
                .tracking(1.0)
                .foregroundStyle(Neon.textTertiary.opacity(0.6))
            Text("WAS WICHTIG WAR.")
                .font(.neonMono(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(accent)
        }
    }

    private var runtimePreparationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(runtimeTint.opacity(0.16))
                    Image(systemName: runtimeIcon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(runtimeTint)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(runtimeTitle)
                        .font(.neonBody(13, weight: .semibold))
                        .foregroundStyle(Neon.textPrimary)
                    Text("WhisperKit/Final-STT und optionale Speaker-Diarization")
                        .font(.neonBody(11))
                        .foregroundStyle(Neon.textTertiary)
                }
                Spacer(minLength: 8)
                if preparationStatus.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                runtimeRow(label: "Sprachmodell", text: speechText, color: speechColor)
                runtimeRow(label: "Speaker-Modell", text: diarizationText, color: diarizationColor)
            }

            if !preparationStatus.canFinishOnboarding && !preparationStatus.isWorking {
                Button("Runtime erneut vorbereiten") {
                    Task { await prepareRuntime() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(runtimeTint.opacity(0.25), lineWidth: Neon.hairlineWidth)
        )
    }

    private func runtimeRow(label: String, text: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.neonMono(10, weight: .semibold))
                .foregroundStyle(Neon.textTertiary)
                .frame(width: 104, alignment: .leading)
            Text(text)
                .font(.neonBody(11))
                .foregroundStyle(Neon.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var runtimeTitle: String {
        if preparationStatus.isWorking { return "Runtime wird vorbereitet" }
        if preparationStatus.canFinishOnboarding { return "Runtime ist bereit" }
        return "Runtime noch nicht bereit"
    }

    private var runtimeIcon: String {
        if preparationStatus.isWorking { return "arrow.down.circle" }
        if preparationStatus.canFinishOnboarding { return "checkmark" }
        return "exclamationmark.triangle"
    }

    private var runtimeTint: Color {
        if preparationStatus.isWorking { return accent }
        if preparationStatus.canFinishOnboarding { return Neon.statusSuccess }
        return Neon.statusWarning
    }

    private var speechText: String {
        switch preparationStatus.speech {
        case .idle: return "Wartet auf Vorbereitung."
        case .preparing(let message): return message
        case .ready(let message): return message
        case .failed(let message): return message
        }
    }

    private var speechColor: Color {
        switch preparationStatus.speech {
        case .ready: return Neon.statusSuccess
        case .failed: return Neon.statusError
        case .preparing: return accent
        case .idle: return Neon.textTertiary
        }
    }

    private var diarizationText: String {
        switch preparationStatus.diarization {
        case .skipped(let message): return message
        case .preparing(let message): return message
        case .ready(let message): return message
        case .failed(let message): return message
        }
    }

    private var diarizationColor: Color {
        switch preparationStatus.diarization {
        case .ready: return Neon.statusSuccess
        case .failed: return Neon.statusWarning
        case .preparing: return accent
        case .skipped: return Neon.textTertiary
        }
    }

    private func prepareRuntimeIfNeeded() async {
        guard !preparationStatus.isWorking, !preparationStatus.canFinishOnboarding else { return }
        await prepareRuntime()
    }

    private func prepareRuntime() async {
        state.runtimePrepared = false
        preparationStatus = .preparing("Bereite Sprachmodell vor ...")
        let snapshot = await appState.prepareFirstRunAssets()
        preparationStatus = snapshot
        state.runtimePrepared = snapshot.canFinishOnboarding
    }
}

struct HotkeyPickerView: View {
    @Binding var parts: [String]
    let accent: Color

    private let presets: [[String]] = [
        ["⌥", "R"],
        ["⌘", "⇧", "R"],
        ["⌃", "⌥", "Q"],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(parts.indices, id: \.self) { idx in
                    BigKbd(text: parts[idx], accent: accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.025))
            )

            HStack(spacing: 6) {
                ForEach(presets.indices, id: \.self) { idx in
                    let preset = presets[idx]
                    let active = preset == parts
                    Button(action: { parts = preset }) {
                        Text(preset.joined(separator: " "))
                            .font(.neonMono(11, weight: .medium))
                            .foregroundStyle(active ? accent : Neon.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(active ? accent.opacity(0.12) : Color.white.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(active ? accent.opacity(0.4) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }
}

struct ReadyVisual: View {
    @ObservedObject var state: OnboardingState
    let accent: Color

    var body: some View {
        VStack(spacing: 16) {
            recordingPill
            macroPillCard
            statsRow
        }
        .frame(width: 380)
    }

    private var recordingPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: 0xFF6259))
                .frame(width: 8, height: 8)
                .modifier(BlinkModifier())
            Text("00:53")
                .font(.neonMono(12, weight: .medium))
                .foregroundStyle(Neon.textPrimary)
                .monospacedDigit()
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { _ in
                    Capsule()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 2, height: CGFloat.random(in: 4...14))
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                Text("Stoppen")
                    .font(.neonBody(11, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color(hex: 0xFF6259)))
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(hex: 0x242422).opacity(0.96))
        )
        .overlay(
            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
    }

    private var macroPillCard: some View {
        VStack(spacing: 14) {
            Text("AUS JEDER APP — DRÜCKE")
                .font(.neonMono(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(accent)

            HStack(spacing: 8) {
                ForEach(state.hotkeyParts.indices, id: \.self) { idx in
                    BigKbd(text: state.hotkeyParts[idx], accent: accent)
                }
            }

            Text("und Quill hört zu.")
                .font(.neonDisplay(18, italic: true))
                .foregroundStyle(Neon.textSecondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statBlock(label: "MIKROFON", value: state.micStatus == .granted ? "✓" : "—")
            statBlock(label: "ENGINE",   value: state.engine == .ane ? "ANE" : "Cloud")
            statBlock(label: "QUELLEN",  value: "\(activeSourceCount)/5")
        }
    }

    private func statBlock(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.neonMono(9))
                .tracking(1.0)
                .foregroundStyle(Neon.textTertiary.opacity(0.6))
            Text(value)
                .font(.neonMono(16, weight: .medium))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }

    private var activeSourceCount: Int {
        [state.captureTeams, state.captureZoom, state.captureMeet,
         state.captureSystem, state.captureLocal].filter { $0 }.count
    }
}
