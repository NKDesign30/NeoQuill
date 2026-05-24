import SwiftUI

// "Wer ist das?"-Sheet — User klickt auf einen anonymen Speaker (S1/S2/...) in der
// Detail-View und tippt den echten Namen ein. Wird im SpeakerStore mit dem aktuellen
// Embedding persistiert → beim nächsten Call automatisch wiedererkannt.

struct SpeakerLabelSheet: View {

    let participant: Participant
    let knownSpeakers: [LabeledSpeaker]
    let suggestedColors: [UInt32]
    var onSave: (String, UInt32, String?) -> Void
    var onDismiss: () -> Void

    @State private var name: String = ""
    @State private var selectedColor: UInt32 = 0x7C8AFF
    @State private var selectedKnownSpeakerId: String?

    private var reusableSpeakers: [LabeledSpeaker] {
        knownSpeakers
            .filter { speaker in
                !LocalSpeakerProfile.isLocalSpeakerId(speaker.id)
                && speaker.id != participant.id
                && !speaker.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in lhs.lastSeenAt > rhs.lastSeenAt }
    }

    private var selectedKnownSpeaker: LabeledSpeaker? {
        reusableSpeakers.first { $0.id == selectedKnownSpeakerId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if !reusableSpeakers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BEKANNTE SPEAKER").neonEyebrow()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(reusableSpeakers) { speaker in
                                Button {
                                    name = speaker.name
                                    selectedColor = speaker.colorHex
                                    selectedKnownSpeakerId = speaker.id
                                } label: {
                                    HStack(spacing: 8) {
                                        Avatar(initials: speaker.id, color: Color(hex: speaker.colorHex), size: 24)
                                        Text(speaker.name)
                                            .font(.neonBody(12, weight: .medium))
                                            .foregroundStyle(Neon.textPrimary)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(
                                                selectedKnownSpeakerId == speaker.id
                                                    ? Neon.brandPrimary
                                                    : Neon.strokeHairline,
                                                lineWidth: selectedKnownSpeakerId == speaker.id
                                                    ? 1
                                                    : Neon.hairlineWidth
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
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
                    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = trimmedName.isEmpty ? participant.name : trimmedName
                    let knownSpeakerId = selectedKnownSpeaker?.name == finalName
                        ? selectedKnownSpeaker?.id
                        : nil
                    onSave(finalName, selectedColor, knownSpeakerId)
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
        .frame(width: 460, height: reusableSpeakers.isEmpty ? 320 : 390)
        .background(Neon.surfaceBackground)
        .onAppear {
            name = participant.name.hasPrefix("Speaker") ? "" : participant.name
            selectedColor = suggestedColors.contains(participant.colorHex)
                ? participant.colorHex
                : (suggestedColors.first ?? 0x7C8AFF)
            selectedKnownSpeakerId = nil
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
