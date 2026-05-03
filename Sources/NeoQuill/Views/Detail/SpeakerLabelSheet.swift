import SwiftUI

// "Wer ist das?"-Sheet — User klickt auf einen anonymen Speaker (S1/S2/...) in der
// Detail-View und tippt den echten Namen ein. Wird im SpeakerStore mit dem aktuellen
// Embedding persistiert → beim nächsten Call automatisch wiedererkannt.

struct SpeakerLabelSheet: View {

    let participant: Participant
    let suggestedColors: [UInt32]
    var onSave: (String, UInt32) -> Void
    var onDismiss: () -> Void

    @State private var name: String = ""
    @State private var selectedColor: UInt32 = 0x7C8AFF

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(alignment: .leading, spacing: 8) {
                Text("NAME").neonEyebrow()
                TextField("Vorname Nachname", text: $name)
                    .textFieldStyle(.plain)
                    .font(.neonBody(15))
                    .foregroundStyle(Neon.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                    )
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("FARBE").neonEyebrow()
                HStack(spacing: 10) {
                    ForEach(suggestedColors, id: \.self) { hex in
                        ColorChip(hex: hex, selected: hex == selectedColor)
                            .onTapGesture { selectedColor = hex }
                    }
                }
            }
            Spacer()
            HStack(spacing: 10) {
                Spacer()
                Button("Abbrechen", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onSave(name.isEmpty ? participant.name : name, selectedColor)
                } label: {
                    Text("Speichern")
                        .font(.neonBodyButton)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 32)
                        .background(Capsule().fill(Neon.brandPrimary))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420, height: 320)
        .background(Neon.surfaceBackground)
        .onAppear {
            name = participant.name.hasPrefix("Speaker") ? "" : participant.name
            selectedColor = suggestedColors.contains(participant.colorHex)
                ? participant.colorHex
                : (suggestedColors.first ?? 0x7C8AFF)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Avatar(initials: participant.id, color: Color(hex: selectedColor), size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("Wer ist das?")
                    .font(.neonDisplay(22))
                    .foregroundStyle(Neon.textPrimary)
                Text("Erkannt als \(participant.id) · NeoQuill merkt sich Stimme + Name fürs nächste Mal.")
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textTertiary)
                    .lineLimit(2)
            }
        }
    }
}

private struct ColorChip: View {
    let hex: UInt32
    let selected: Bool

    var body: some View {
        Circle()
            .fill(Color(hex: hex))
            .frame(width: 26, height: 26)
            .overlay(
                Circle()
                    .stroke(selected ? Neon.textPrimary : .clear, lineWidth: 2)
                    .padding(-3)
            )
    }
}
