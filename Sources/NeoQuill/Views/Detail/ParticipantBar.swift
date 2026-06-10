import SwiftUI

// Sprechanteil-Bar pro Teilnehmer: Avatar | Name+Role+spoke%/time | Bar.

struct ParticipantBar: View {
    let participant: Participant
    let totalSeconds: Int
    var accent: Color = Neon.brandPrimary

    @EnvironmentObject private var state: AppState
    @State private var showLabelSheet = false

    private var spokeSeconds: Int { SpokenDuration.seconds(from: participant.spoke) ?? 0 }
    private var percent: Int {
        guard totalSeconds > 0 else { return 0 }
        return Int((Double(spokeSeconds) / Double(totalSeconds)) * 100.0)
    }

    private var isAnonymous: Bool {
        SpeakerPalette.isAnonymousSpeaker(id: participant.id, name: participant.name)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if isAnonymous { showLabelSheet = true }
            } label: {
                Avatar(initials: participant.id, color: participant.color, size: 28)
                    .overlay(alignment: .bottomTrailing) {
                        if isAnonymous {
                            Circle()
                                .fill(Neon.brandPrimary)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Image(systemName: "pencil")
                                        .font(.system(size: 6, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                                .offset(x: 2, y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(participant.name)
                        .font(.neonBody(13, weight: .medium))
                        .foregroundStyle(Neon.textPrimary)
                    Text(participant.role)
                        .font(.neonBody(12))
                        .foregroundStyle(Neon.textTertiary)
                    Spacer(minLength: 8)
                    Text("\(participant.spoke) · \(percent)%")
                        .font(.neonMono(11))
                        .foregroundStyle(Neon.textTertiary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    let w = max(0, geo.size.width * Double(percent) / 100)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule().fill(participant.color).frame(width: w)
                    }
                }
                .frame(height: 4)
            }
        }
        .sheet(isPresented: $showLabelSheet) {
            SpeakerLabelSheet(
                participant: participant,
                knownSpeakers: state.speakerStore.speakers,
                suggestedColors: [0x2EAB73, 0x7C8AFF, 0xFFB340, 0x409CFF, 0xD4845A, 0xFF6259],
                onSave: { name, color, knownSpeakerId in
                    let migrated = state.recorder.labelSpeaker(
                        internalId: participant.id,
                        name: name,
                        colorHex: color,
                        meetingId: state.selectedMeetingId,
                        knownSpeakerId: knownSpeakerId
                    )
                    if migrated > 0 {
                        let suffix = migrated == 1 ? "weiteres Meeting" : "weitere Meetings"
                        state.notify("\(name) in \(migrated) \(suffix) erkannt")
                    } else {
                        state.notify("\(name) gespeichert")
                    }
                    showLabelSheet = false
                },
                onDismiss: { showLabelSheet = false }
            )
        }
    }

}
