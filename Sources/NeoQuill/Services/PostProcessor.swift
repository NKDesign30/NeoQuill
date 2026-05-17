import Foundation

// Post-Processing nach Stop: WAV speichern + optional Claude-Summary holen.
// Orchestriert AudioWriter (Mix → ~/Library/Application Support/NeoQuill/recordings)
// und ClaudeCLIClient (Haiku via Max-Plan, kein API-Key nötig).

struct PostProcessResult {
    let title: String
    let tldr: String
    let highlights: [HighlightAI]
    let tasks: [TaskAI]
    let chapters: [ChapterAI]
    let audioURL: URL?
}

enum PostProcessor {

    static func process(
        meetingId: String,
        mixedSamples: [Float],
        transcriptLines: [TranscriptLine],
        locale: String = "de"
    ) async -> PostProcessResult {
        let audioURL = persistAudio(meetingId: meetingId, samples: mixedSamples)

        let transcript = Self.formatTranscriptForPrompt(transcriptLines)

        guard !transcript.isEmpty else {
            return PostProcessResult(
                title: "Aufnahme ohne Sprache",
                tldr: "Keine Sprach-Inhalte erkannt.",
                highlights: [],
                tasks: [],
                chapters: [],
                audioURL: audioURL
            )
        }

        let ai = await summarize(transcript: transcript, locale: locale)

        return PostProcessResult(
            title: ai?.title ?? fallbackTitle(from: transcriptLines),
            tldr: ai?.tldr ?? fallbackTldr(from: transcriptLines),
            highlights: ai?.highlights ?? [],
            tasks: ai?.tasks ?? [],
            chapters: ai?.chapters ?? [],
            audioURL: audioURL
        )
    }

    private static func persistAudio(meetingId: String, samples: [Float]) -> URL? {
        guard !samples.isEmpty else { return nil }
        let writer = AudioWriter()
        do {
            try writer.start(id: meetingId)
            writer.write(samples: samples)
            return writer.close()
        } catch {
            NSLog("[PostProcessor] AudioWriter failed: \(error)")
            return nil
        }
    }

    private static func summarize(transcript: String, locale: String) async -> MeetingSummaryAI? {
        guard !UserDefaults.standard.boolOr(AppSettings.localOnlyMode, default: false) else { return nil }
        guard UserDefaults.standard.boolOr(AppSettings.claudeAnalysisEnabled, default: true) else { return nil }

        switch AIProviderSettings.selectedProvider() {
        case .claudeCLI:
            return await ClaudeCLIClient.summarize(transcript: transcript, locale: locale)
        case .openAICompatible:
            guard let config = AIProviderSettings.openAICompatibleConfig() else {
                NSLog("[PostProcessor] OpenAI-compatible provider missing config or API key")
                return nil
            }
            return await OpenAICompatibleSummaryClient.summarize(
                transcript: transcript,
                locale: locale,
                config: config
            )
        }
    }

    /// Formatiert die TranscriptLines fuer den Claude-Prompt und kuerzt
    /// lange Meetings (>500 Lines) symmetrisch (erste + letzte Lines)
    /// damit der Prompt unter 100 KB bleibt und der ganze Meeting-Bogen
    /// (Anfang + Ende) erhalten bleibt.
    private static let maxLines = 500
    private static func formatTranscriptForPrompt(_ lines: [TranscriptLine]) -> String {
        let format: (TranscriptLine) -> String = { "\($0.who) [\($0.timestamp)]: \($0.body)" }
        if lines.count <= maxLines {
            return lines.map(format).joined(separator: "\n")
        }
        let head = lines.prefix(maxLines / 2).map(format)
        let tail = lines.suffix(maxLines / 2).map(format)
        let omitted = lines.count - head.count - tail.count
        let marker = "\n\n[... \(omitted) Lines des Mittelteils gekuerzt — Anfang und Ende voll ...]\n\n"
        return (head.joined(separator: "\n")) + marker + (tail.joined(separator: "\n"))
    }

    private static func fallbackTitle(from lines: [TranscriptLine]) -> String {
        guard let first = lines.first?.body, !first.isEmpty else { return "Aufnahme" }
        return first.split(separator: " ").prefix(7).joined(separator: " ")
    }

    private static func fallbackTldr(from lines: [TranscriptLine]) -> String {
        guard let first = lines.first?.body else { return "—" }
        return String(first.prefix(220))
    }
}
