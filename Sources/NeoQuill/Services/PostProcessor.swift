import Foundation

// Post-Processing nach Stop: WAV speichern + Claude-Summary holen.
// Orchestriert AudioWriter (Mix → ~/Library/Application Support/NeoQuill/recordings)
// und ClaudeCLIClient (Haiku via Max-Plan, kein API-Key nötig).

struct PostProcessResult {
    let title: String
    let tldr: String
    let highlights: [HighlightAI]
    let tasks: [TaskAI]
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

        let transcript = transcriptLines
            .map { "\($0.who) [\($0.timestamp)]: \($0.body)" }
            .joined(separator: "\n")

        guard !transcript.isEmpty else {
            return PostProcessResult(
                title: "Aufnahme ohne Sprache",
                tldr: "Keine Sprach-Inhalte erkannt.",
                highlights: [],
                tasks: [],
                audioURL: audioURL
            )
        }

        let ai = await ClaudeCLIClient.summarize(transcript: transcript, locale: locale)

        return PostProcessResult(
            title: ai?.title ?? fallbackTitle(from: transcriptLines),
            tldr: ai?.tldr ?? fallbackTldr(from: transcriptLines),
            highlights: ai?.highlights ?? [],
            tasks: ai?.tasks ?? [],
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

    private static func fallbackTitle(from lines: [TranscriptLine]) -> String {
        guard let first = lines.first?.body, !first.isEmpty else { return "Aufnahme" }
        return first.split(separator: " ").prefix(7).joined(separator: " ")
    }

    private static func fallbackTldr(from lines: [TranscriptLine]) -> String {
        guard let first = lines.first?.body else { return "—" }
        return String(first.prefix(220))
    }
}
