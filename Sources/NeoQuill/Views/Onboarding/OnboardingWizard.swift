import SwiftUI

// First-Run-Wizard nach Design (quill/project/onboarding.jsx).
// Editorial-Layout: links Eyebrow → Display-Headline → Lead → Form,
// rechts kontextuelles Visual auf subtil gegridetem Hintergrund.
// Footer: Zurück + StepDots + PrimaryCTA.

struct OnboardingWizard: View {

    @StateObject private var state = OnboardingState()
    @EnvironmentObject private var appState: AppState
    var onFinish: () -> Void

    private let accent: Color = Neon.brandPrimary

    var body: some View {
        VStack(spacing: 0) {
            stepBody
            footer
        }
        .frame(width: 1180, height: 800)
        .background(Color(hex: 0x0E0E0D))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 36, y: 10)
        .onAppear { state.refreshPermissionStates() }
    }

    @ViewBuilder
    private var stepBody: some View {
        let total = OnboardingState.Step.allCases.count
        OnboardingStepShell(
            stepIdx: state.currentStep.rawValue,
            total: total,
            eyebrow: state.currentStep.eyebrow,
            accent: accent,
            content: { content },
            visual: { visual }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state.currentStep {
        case .welcome:    WelcomeContent(accent: accent)
        case .microphone: MicrophoneContent(state: state, accent: accent)
        case .voice:      VoiceContent(state: state, enrollment: appState.voiceIdEnrollment, accent: accent)
        case .engine:     EngineContent(state: state, accent: accent)
        case .capture:    CaptureContent(state: state, accent: accent)
        case .ready:      ReadyContent(state: state, accent: accent)
        }
    }

    @ViewBuilder
    private var visual: some View {
        switch state.currentStep {
        case .welcome:    WelcomeVisual(accent: accent)
        case .microphone: MicVisual(accent: accent, granted: state.micStatus == .granted)
        case .voice:      VoiceVisual(state: state, enrollment: appState.voiceIdEnrollment, accent: accent)
        case .engine:     EngineVisual(state: state, accent: accent)
        case .capture:    CaptureVisual(state: state, accent: accent)
        case .ready:      ReadyVisual(state: state, accent: accent)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            backButton
            Spacer()
            OnboardingStepDots(total: OnboardingState.Step.allCases.count,
                               active: state.currentStep.rawValue,
                               accent: accent)
            Spacer()
            HStack(spacing: 8) {
                if let secondary = state.secondaryLabel {
                    Button(action: { state.skip() }) {
                        Text(secondary)
                            .font(.neonBody(13, weight: .medium))
                            .foregroundStyle(Neon.textSecondary)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
                primaryButton
            }
        }
        .padding(.horizontal, 32)
        .frame(height: 72)
        .background(Color.white.opacity(0.02))
        .overlay(
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth),
            alignment: .top
        )
    }

    private var backButton: some View {
        Button(action: { state.goBack() }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(180))
                    .font(.system(size: 11, weight: .semibold))
                Text("Zurück")
                    .font(.neonBody(13, weight: .medium))
            }
            .foregroundStyle(state.canGoBack ? Neon.textSecondary : Neon.textTertiary.opacity(0.4))
            .padding(.horizontal, 14)
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!state.canGoBack)
    }

    private var primaryButton: some View {
        Button(action: handlePrimary) {
            HStack(spacing: 8) {
                Text(state.primaryLabel)
                    .font(.neonBody(13, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(state.canGoNext ? accent : accent.opacity(0.5))
                    .shadow(color: accent.opacity(0.35), radius: 14, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(!state.canGoNext)
        .keyboardShortcut(.defaultAction)
    }

    private func handlePrimary() {
        switch state.currentStep {
        case .microphone where state.micStatus != .granted:
            Task { await state.requestMicPermission() }
        case .ready:
            state.persistAll()
            onFinish()
        default:
            state.advance()
        }
    }
}

// MARK: - Step Shell

struct OnboardingStepShell<Content: View, Visual: View>: View {
    let stepIdx: Int
    let total: Int
    let eyebrow: String
    let accent: Color
    @ViewBuilder var content: Content
    @ViewBuilder var visual: Visual

    var body: some View {
        HStack(spacing: 0) {
            // Linke Hälfte — Copy + Form
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 36) {
                    OnboardingEyebrow(stepIdx: stepIdx, total: total, eyebrow: eyebrow, accent: accent)
                    content
                }
                .padding(.top, 56)
                .padding(.bottom, 40)
                .padding(.horizontal, 56)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)

            // Rechte Hälfte — Visual
            ZStack {
                Color.white.opacity(0.015)
                Rectangle()
                    .fill(LinearGradient(
                        colors: [accent.opacity(0.06), .clear],
                        startPoint: .top, endPoint: .center))
                OnboardingGridBackground()
                visual
                    .padding(48)
                    .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                Rectangle().fill(Neon.strokeHairline).frame(width: Neon.hairlineWidth),
                alignment: .leading
            )
        }
    }
}

private struct OnboardingEyebrow: View {
    let stepIdx: Int
    let total: Int
    let eyebrow: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d / %02d", stepIdx + 1, total))
                .font(.neonMono(10, weight: .semibold))
                .foregroundStyle(accent)
                .monospacedDigit()
            Text("·")
                .foregroundStyle(Neon.textTertiary.opacity(0.4))
            Text(eyebrow)
                .font(.neonMono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(accent)
        }
    }
}

private struct OnboardingGridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 48
            var path = Path()
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(Color.white.opacity(0.02)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private struct OnboardingStepDots: View {
    let total: Int
    let active: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { idx in
                let isCurrent = idx == active
                let isDone = idx < active
                Capsule()
                    .fill(isCurrent ? accent : (isDone ? accent.opacity(0.5) : Color.white.opacity(0.14)))
                    .frame(width: isCurrent ? 22 : 5, height: 5)
                    .animation(.easeOut(duration: 0.22), value: active)
            }
        }
    }
}

// MARK: - Reusable bits

struct OnboardingHeading: View {
    let title: String
    let italicSuffix: String?
    let lead: String
    let accent: Color
    let maxLeadWidth: CGFloat

    init(title: String, italicSuffix: String? = nil, lead: String, accent: Color, maxLeadWidth: CGFloat = 460) {
        self.title = title
        self.italicSuffix = italicSuffix
        self.lead = lead
        self.accent = accent
        self.maxLeadWidth = maxLeadWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.neonDisplay(48))
                    .foregroundStyle(Neon.textPrimary)
                    .lineSpacing(-2)
                if let italicSuffix {
                    Text(italicSuffix)
                        .font(.neonDisplay(48, italic: true))
                        .foregroundStyle(accent)
                }
            }
            .multilineTextAlignment(.leading)
            Text(lead)
                .font(.neonAlt(15))
                .foregroundStyle(Neon.textSecondary)
                .lineSpacing(4)
                .frame(maxWidth: maxLeadWidth, alignment: .leading)
        }
    }
}

struct OnboardingFormLabel: View {
    let text: String
    var hint: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.neonMono(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Neon.textTertiary)
            if let hint {
                Text(hint)
                    .font(.neonMono(10))
                    .foregroundStyle(Neon.textTertiary.opacity(0.6))
            }
        }
    }
}

struct OnboardingTextField: View {
    @Binding var text: String
    let placeholder: String
    let accent: Color
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.neonAlt(15))
            .foregroundStyle(Neon.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(focused ? 0.06 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(focused ? accent.opacity(0.55) : Neon.strokeHairline, lineWidth: focused ? 1 : Neon.hairlineWidth)
            )
            .focused($focused)
    }
}

struct OnboardingToggleRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    var badge: String? = nil
    @Binding var value: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(value ? accent.opacity(0.12) : Color.white.opacity(0.04))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(value ? accent.opacity(0.4) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(value ? accent : Neon.textSecondary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.neonBody(14, weight: .medium))
                        .foregroundStyle(Neon.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.neonMono(9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(accent.opacity(0.12))
                            )
                    }
                }
                Text(subtitle)
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            OnboardingSwitch(value: $value, accent: accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }
}

struct OnboardingSwitch: View {
    @Binding var value: Bool
    let accent: Color

    var body: some View {
        Button(action: { value.toggle() }) {
            ZStack(alignment: value ? .trailing : .leading) {
                Capsule()
                    .fill(value ? accent : Color.white.opacity(0.10))
                    .frame(width: 38, height: 22)
                    .overlay(
                        Capsule().stroke(value ? accent.opacity(0.5) : Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                    )
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 3)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            .frame(width: 38, height: 22)
            .animation(.easeOut(duration: 0.18), value: value)
        }
        .buttonStyle(.plain)
    }
}

struct PromiseCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(accent.opacity(0.12))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(accent)
            }
            .frame(width: 28, height: 28)
            Text(title)
                .font(.neonBody(13, weight: .medium))
                .foregroundStyle(Neon.textPrimary)
            Text(subtitle)
                .font(.neonBody(12))
                .foregroundStyle(Neon.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
    }
}

struct BigKbd: View {
    let text: String
    let accent: Color

    var body: some View {
        Text(text)
            .font(.neonMono(18, weight: .medium))
            .foregroundStyle(Neon.textPrimary)
            .frame(minWidth: 40, minHeight: 40)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: 0x242422).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accent.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: accent.opacity(0.2), radius: 0, y: 2)
    }
}
