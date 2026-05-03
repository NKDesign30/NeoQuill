import SwiftUI
import UniformTypeIdentifiers

struct ImportTranscriptSheet: View {
    let meetingId: String
    let meetingTitle: String
    let onComplete: (Result<PlatformImportService.Outcome, Error>) -> Void

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var pickedURL: URL?
    @State private var preview: PreviewState = .none
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transkript importieren")
                .font(.neonDisplay(20))
                .foregroundStyle(Neon.textPrimary)

            Text("Meeting: \(meetingTitle)")
                .font(.neonBody(12))
                .foregroundStyle(Neon.textSecondary)

            Divider()

            if let url = pickedURL {
                fileSummary(url)
            } else {
                emptyChooser
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Abbrechen") {
                    onComplete(.success(PlatformImportService.Outcome(platform: .meet, events: [])))
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if pickedURL != nil {
                    Button("Andere Datei") { openPicker() }
                }

                Button(isImporting ? "Importiert…" : "Anwenden") { applyImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply)
            }
        }
        .padding(24)
        .frame(width: 480, height: 320)
        .preferredColorScheme(.dark)
        .background(Neon.windowBackdrop)
        .onAppear {
            if pickedURL == nil { openPicker() }
        }
    }

    private var canApply: Bool {
        guard !isImporting else { return false }
        if case .ready = preview { return true }
        return false
    }

    @ViewBuilder
    private var emptyChooser: some View {
        VStack(spacing: 12) {
            GlyphView(name: .download, size: 32, color: Neon.textTertiary)
            Text("Wähle eine Transkriptdatei (.vtt oder .json)")
                .font(.neonBody(13))
                .foregroundStyle(Neon.textSecondary)
            Button("Datei auswählen") { openPicker() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func fileSummary(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GlyphView(name: .download, size: 14, color: Neon.brandPrimary)
                Text(url.lastPathComponent)
                    .font(.neonMono(12, weight: .medium))
                    .foregroundStyle(Neon.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            switch preview {
            case .none:
                Text("Lese Datei…")
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textTertiary)
            case .ready(let outcome):
                Text("Erkannt: \(formatLabel(for: outcome.platform)) · \(outcome.events.count) Einträge")
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textSecondary)
                if let firstSpeaker = outcome.events.compactMap(\.speakerName).first {
                    Text("Erster Speaker: \(firstSpeaker)")
                        .font(.neonBody(11))
                        .foregroundStyle(Neon.textTertiary)
                }
            case .error(let message):
                Text(message)
                    .font(.neonBody(12))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
        }
    }

    private func openPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "vtt") ?? .data,
            .json
        ]
        panel.prompt = "Importieren"
        panel.message = "Wähle ein Plattform-Transkript (Teams VTT/Metadata, Meet Entries, Zoom Timeline/VTT)."
        if panel.runModal() == .OK, let url = panel.url {
            pickedURL = url
            previewFile(url)
        }
    }

    private func previewFile(_ url: URL) {
        do {
            let outcome = try PlatformImportService.detectAndParse(url: url)
            preview = .ready(outcome)
        } catch {
            preview = .error(error.localizedDescription)
        }
    }

    private func applyImport() {
        guard let url = pickedURL, case .ready = preview else { return }
        isImporting = true
        do {
            let outcome = try state.importPlatformTranscript(meetingId: meetingId, fileURL: url)
            onComplete(.success(outcome))
        } catch {
            onComplete(.failure(error))
        }
        isImporting = false
        dismiss()
    }

    private func formatLabel(for platform: Platform) -> String {
        switch platform {
        case .teams: return "Microsoft Teams"
        case .meet:  return "Google Meet"
        case .zoom:  return "Zoom"
        case .call:  return "Generischer Call"
        }
    }

    private enum PreviewState {
        case none
        case ready(PlatformImportService.Outcome)
        case error(String)
    }
}
