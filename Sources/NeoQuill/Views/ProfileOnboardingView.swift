import SwiftUI

struct ProfileOnboardingView: View {
    var onComplete: (String, String) -> Void

    @State private var name: String = LocalSpeakerProfile.displayName == "Ich" ? "" : LocalSpeakerProfile.displayName
    @State private var role: String = LocalSpeakerProfile.role

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            fields
            footer
        }
        .padding(28)
        .frame(width: 460)
        .background(Neon.surfaceBackground)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(initials: LocalSpeakerProfile.id, color: Color(hex: LocalSpeakerProfile.colorHex), size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dein Profil")
                    .font(.neonDisplay(24))
                    .foregroundStyle(Neon.textPrimary)
                Text("NeoQuill nutzt das für deine Mikrofonspur. Bleibt lokal.")
                    .font(.neonBody(13))
                    .foregroundStyle(Neon.textTertiary)
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NAME").neonEyebrow()
                TextField("Vorname Nachname", text: $name)
                    .textFieldStyle(.plain)
                    .font(.neonBody(15))
                    .foregroundStyle(Neon.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("ROLLE").neonEyebrow()
                TextField("Eigene Stimme", text: $role)
                    .textFieldStyle(.plain)
                    .font(.neonBody(15))
                    .foregroundStyle(Neon.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth))
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                onComplete(name, role)
            } label: {
                Text("Weiter")
                    .font(.neonBodyButton)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(Capsule().fill(canContinue ? Neon.brandPrimary : Neon.textTertiary.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
        }
    }
}
