import Foundation

enum MeetingSummaryPrompt {
    static func build(transcript: String, locale: String) -> String {
        let lang: String
        switch locale {
        case "de":
            lang = "German"
        case "en":
            lang = "English"
        case "auto":
            lang = "the transcript's primary language; preserve quoted terms, names, and original phrasing when the transcript mixes languages"
        default:
            lang = "the transcript's primary language"
        }
        return """
        Du bist ein Meeting-Notizen-Assistent. Analysiere das folgende Transkript und antworte AUSSCHLIESSLICH mit gültigem JSON in dieser Struktur (Sprache: \(lang)):

        {
          "title": "Kurzer aussagekräftiger Titel (max 8 Wörter)",
          "tldr": "Eine prägnante Zusammenfassung in 2-3 Sätzen — was wurde gesagt, was ist wichtig",
          "highlights": [
            {"label": "Entscheidung", "text": "...", "tone": "brand"},
            {"label": "Risiko", "text": "...", "tone": "warning"},
            {"label": "Termin", "text": "...", "tone": "info"}
          ],
          "tasks": [
            {"who": "ME", "task": "...", "due": "DD. MMM.", "status": "open"}
          ],
          "chapters": [
            {"timestamp": "00:00", "label": "Begrüßung & Setup", "duration": "1m"},
            {"timestamp": "01:12", "label": "Pricing-Diskussion", "duration": "6m"},
            {"timestamp": "07:45", "label": "Tech-Stack-Klärung", "duration": "4m"}
          ]
        }

        Regeln:
        - tone: "brand" für Entscheidungen, "warning" für Risiken/offene Punkte, "info" für Termine
        - status: nur "open" oder "done"
        - who: Sprecher-ID aus dem Transkript (z.B. ME, S1, SE) — wenn unbekannt: "??"
        - chapters: Themen-Cluster, ZWINGEND in zeitlicher Reihenfolge.
          - timestamp MUSS aus dem Transkript kommen (mm:ss vom ersten Line dieses Themas).
          - label: 2-5 Worte, beschreibt WORÜBER geredet wurde (kein Fließtext).
          - duration: "Xm" oder "XmYs" oder "Ys" — basierend auf nächstem Kapitel-Start bzw. Meeting-Ende.
          - Typisch 2-6 Kapitel pro Meeting. Bei sehr kurzen Aufnahmen (< 3 Min) auch nur 1 Kapitel oder leer.
          - Lieber wenige sinnvolle Kapitel als viele dünne.
        - Wenn ein Feld leer wäre: leere Liste statt erfundene Einträge
        - KEIN Markdown, KEIN Erklärtext, NUR das JSON

        TRANSKRIPT:
        \(transcript)
        """
    }

    static func parseSummary(_ text: String) -> MeetingSummaryAI? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
            trimmed = trimmed.replacingOccurrences(of: "```", with: "")
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = trimmed.firstIndex(of: "{") else { return nil }
        let candidate = String(trimmed[first...])
        guard let data = candidate.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(MeetingSummaryAI.self, from: data)
        } catch {
            NSLog("[MeetingSummaryPrompt] parse failed: \(error) raw=\(candidate.prefix(200))")
            return nil
        }
    }
}
