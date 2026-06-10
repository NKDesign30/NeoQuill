import Foundation

// Das gemeinsame Ergebnis-Vokabular ALLER Summary-Provider (Claude CLI,
// OpenAI-kompatibel, Anthropic, Ollama) und der Input von MeetingSummarizer.
// Lebte historisch im ClaudeCLIClient — die anderen Provider hingen damit
// still von der CLI-Datei ab.

struct MeetingSummaryAI: Codable {
    let title: String
    let tldr: String
    let highlights: [HighlightAI]
    let tasks: [TaskAI]
    let chapters: [ChapterAI]

    // Defensive: wenn das Modell einen Key komplett vergisst, fallen wir auf
    // sinnvolle Defaults statt den ganzen Decode zu killen. Sonst geht
    // ein einzelner fehlender Key (z.B. chapters) als nil-Summary zurück
    // und der User sieht weder TLDR noch Highlights.
    enum CodingKeys: String, CodingKey {
        case title, tldr, highlights, tasks, chapters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title      = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.tldr       = (try? c.decode(String.self, forKey: .tldr)) ?? ""
        self.highlights = (try? c.decode([HighlightAI].self, forKey: .highlights)) ?? []
        self.tasks      = (try? c.decode([TaskAI].self, forKey: .tasks)) ?? []
        self.chapters   = (try? c.decode([ChapterAI].self, forKey: .chapters)) ?? []
    }

    init(title: String, tldr: String, highlights: [HighlightAI], tasks: [TaskAI], chapters: [ChapterAI]) {
        self.title = title
        self.tldr = tldr
        self.highlights = highlights
        self.tasks = tasks
        self.chapters = chapters
    }
}

struct HighlightAI: Codable {
    let label: String      // "Entscheidung" / "Risiko" / "Termin"
    let text: String
    let tone: String       // "brand" / "warning" / "info"
}

struct TaskAI: Codable {
    let who: String
    let task: String
    let due: String
    let status: String     // "open" / "done"
}

struct ChapterAI: Codable {
    let timestamp: String  // "02:14" — Anfang des Themen-Blocks im Audio
    let label: String      // "Pricing-Diskussion" — 2-5 Worte
    let duration: String   // "6m" oder "45s"
}
