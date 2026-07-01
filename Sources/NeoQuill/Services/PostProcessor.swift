import Foundation

// Post-Processing nach Stop: aus dem Transkript eine Summary holen
// (Titel, TLDR, Highlights, Tasks, Chapters). Das WAV schreibt der
// RecordingController selbst via AudioWriter — hier läuft kein Audio mehr.
// Provider wird über AIProviderSettings.makeProvider aufgelöst (Claude CLI,
// OpenAI-kompatibel, Anthropic, Ollama). Der PostProcessor kennt nur SummaryProvider.

struct PostProcessResult {
    let title: String
    let tldr: String
    let highlights: [HighlightAI]
    let tasks: [TaskAI]
    let chapters: [ChapterAI]
}

enum PostProcessor {

    static func process(
        meetingId: String,
        transcriptLines: [TranscriptLine],
        locale: String = "auto",
        context: String? = nil,
        licenseAllowsSummary: () -> Bool = { true },
        defaults: UserDefaults = .standard,
        providerFactory: () -> SummaryProvider? = { AIProviderSettings.makeProvider() }
    ) async -> PostProcessResult {
        let transcript = Self.formatTranscriptForPrompt(transcriptLines)

        guard !transcript.isEmpty else {
            return PostProcessResult(
                title: "Aufnahme ohne Sprache",
                tldr: "Keine Sprach-Inhalte erkannt.",
                highlights: [],
                tasks: [],
                chapters: []
            )
        }

        // Lizenz-Gate. Recording + Transkript bleiben frei, nur die
        // AI-Summary-Stufe ist Pro. Bei block: Fallback-Title/TLDR aus
        // erstem Transkript-Satz, keine Highlights/Tasks/Chapters.
        let promptInput = Self.promptInput(transcript: transcript, context: context)
        let ai: MeetingSummaryAI? = licenseAllowsSummary()
            ? await summarize(transcript: promptInput, locale: locale, defaults: defaults, providerFactory: providerFactory)
            : nil

        return PostProcessResult(
            title: ai?.title ?? fallbackTitle(from: transcriptLines),
            tldr: ai?.tldr ?? fallbackTldr(from: transcriptLines),
            highlights: ai?.highlights ?? [],
            tasks: ai?.tasks ?? [],
            chapters: ai?.chapters ?? []
        )
    }

    /// `nil` = Summary darf laufen. Sonst der konkrete Grund fürs Überspringen —
    /// landet im Log statt eines stummen `return nil`. Hier leben die beiden
    /// nutzer-konfigurierten Schalter (Local-Only, KI-Analyse); das Lizenz-Gate
    /// bleibt bewusst die injizierte Closure des Aufrufers.
    private static func summarySkipReason(defaults: UserDefaults) -> String? {
        if defaults.boolOr(AppSettings.localOnlyMode, default: false) {
            return "Local-Only-Modus aktiv"
        }
        if !defaults.boolOr(AppSettings.claudeAnalysisEnabled, default: true) {
            return "KI-Analyse in den Einstellungen deaktiviert"
        }
        return nil
    }

    private static func summarize(
        transcript: String,
        locale: String,
        defaults: UserDefaults,
        providerFactory: () -> SummaryProvider?
    ) async -> MeetingSummaryAI? {
        if let reason = summarySkipReason(defaults: defaults) {
            NSLog("[PostProcessor] summary skipped: \(reason)")
            return nil
        }
        guard let provider = providerFactory() else {
            NSLog("[PostProcessor] no summary provider configured (missing config or API key)")
            return nil
        }
        return await provider.summarize(transcript: transcript, locale: locale)
    }

    /// Formatiert die TranscriptLines fuer den Summary-Prompt und kuerzt
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

    private static func promptInput(transcript: String, context: String?) -> String {
        guard let context = context?.trimmingCharacters(in: .whitespacesAndNewlines),
              !context.isEmpty else {
            return transcript
        }
        return """
        Workspace-Kontext:
        \(context)

        Transkript:
        \(transcript)
        """
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
