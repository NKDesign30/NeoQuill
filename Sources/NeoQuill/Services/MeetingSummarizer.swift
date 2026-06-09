import Foundation

/// Das fertige, in Domain-Typen gemappte Ergebnis der KI-Zusammenfassung.
struct MeetingSummaryResult {
    let title: String
    let tldr: String
    let highlights: [Highlight]
    let tasks: [ActionItem]
    let chapters: [Chapter]
}

/// Ruft den `PostProcessor` und übersetzt sein Roh-Ergebnis (`HighlightAI`,
/// `TaskAI`, `ChapterAI`) in fertige Domain-Typen.
///
/// Vorher lief dieser Schluss-Abschnitt in vier Methoden des `RecordingController`
/// fast wortgleich (`persistMeeting`, `persistImportedMeeting`,
/// `mergeAudioIntoMeeting`, `reprocessMeetingAsync`): derselbe
/// `PostProcessor.process`-Aufruf, dasselbe Highlights/Tasks/Chapters-Mapping —
/// rund zweihundert Zeilen Duplikation. Die einzige echte Divergenz war ein
/// ID-Prefix (`-task-` vs `-merge-task-` vs `-reprocess-task-`), der die
/// task-/chapter-IDs pro Pfad eindeutig hält. Genau das war eine latente
/// Drift-Bug-Quelle: änderte jemand das Mapping nur an einer Stelle, liefen die
/// vier Pfade auseinander. Jetzt gibt es ein Mapping, parametrisiert per `idPrefix`.
enum MeetingSummarizer {

    /// Ruft den PostProcessor und mappt sein Ergebnis in Domain-Typen. `idPrefix`
    /// (z.B. `""`, `"merge-"`, `"reprocess-"`) hält die task-/chapter-IDs pro
    /// Pfad eindeutig.
    static func summarize(
        meetingId: String,
        idPrefix: String = "",
        transcriptLines: [TranscriptLine],
        locale: String,
        licenseAllowsSummary: () -> Bool
    ) async -> MeetingSummaryResult {
        let result = await PostProcessor.process(
            meetingId: meetingId,
            transcriptLines: transcriptLines,
            locale: locale,
            licenseAllowsSummary: licenseAllowsSummary
        )
        return MeetingSummaryResult(
            title: result.title,
            tldr: result.tldr,
            highlights: result.highlights.map(mapHighlight),
            tasks: mapTasks(result.tasks, meetingId: meetingId, idPrefix: idPrefix),
            chapters: mapChapters(result.chapters, meetingId: meetingId, idPrefix: idPrefix)
        )
    }

    /// Internal für Tests: reines Mapping ohne PostProcessor-Aufruf.
    static func mapTasks(_ tasks: [TaskAI], meetingId: String, idPrefix: String) -> [ActionItem] {
        tasks.enumerated().map { idx, t in
            ActionItem(
                id: "\(meetingId)-\(idPrefix)task-\(idx)",
                who: t.who.isEmpty ? "??" : t.who,
                task: t.task,
                due: t.due,
                status: t.status == "done" ? .done : .open
            )
        }
    }

    static func mapChapters(_ chapters: [ChapterAI], meetingId: String, idPrefix: String) -> [Chapter] {
        chapters.enumerated().map { idx, c in
            Chapter(
                id: "\(meetingId)-\(idPrefix)ch-\(idx)",
                timestamp: c.timestamp,
                label: c.label,
                duration: c.duration
            )
        }
    }

    static func mapHighlight(_ ai: HighlightAI) -> Highlight {
        let tone: HighlightTone
        switch ai.tone.lowercased() {
        case "warning":  tone = .warning
        case "info":     tone = .info
        default:         tone = .brand
        }
        return Highlight(label: ai.label, text: ai.text, tone: tone)
    }
}
