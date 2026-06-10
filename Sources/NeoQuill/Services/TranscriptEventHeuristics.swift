import Foundation

/// Geteilte Heuristiken der Transcript-Event-Produktion (Platform-Parser,
/// AX-Captions, VTT-Cues, Fixtures).
///
/// Dieselben zwei Fragen — "ist das ein Sprechername?" und "wie lange dauert
/// dieser Text gesprochen?" — wurden vorher an drei bzw. drei Stellen separat
/// beantwortet, mit bereits passiertem Drift: `CaptionFixtureReplayer`
/// behauptete im Kommentar, analog zum `CaptionTextParser` zu rechnen, nutzte
/// aber eine andere Formel (words×0.45 statt words/2.4) — und ein Test pinnte
/// den Drift fest. Die Profile unterscheiden sich pro Quelle nur in den
/// dokumentierten Parametern, nicht in der Logik.
enum TranscriptEventHeuristics {

    /// Sieht `candidate` wie ein Sprechername aus (Teil vor dem Doppelpunkt)?
    ///
    /// - `minLength`: AX-Captions und JSON-Parser verlangen 2 Zeichen;
    ///   VTT erlaubt 1 (anonymisierte "A:"-Speaker sind dort üblich).
    /// - `maxWords`: AX/JSON 5; VTT 6 (lange Roster-Display-Namen).
    /// - `blockedFragments`: AX-Captions filtern UI-Begriffe, die im
    ///   Fenstertext wie ein Name aussehen ("Untertitel", "Caption", …).
    static func isProbableSpeakerName(
        _ candidate: String,
        minLength: Int = 2,
        maxWords: Int = 5,
        blockedFragments: [String] = []
    ) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (minLength...64).contains(trimmed.count) else { return false }
        guard trimmed.rangeOfCharacter(from: .letters) != nil else { return false }
        if !blockedFragments.isEmpty {
            let lower = trimmed.lowercased()
            if blockedFragments.contains(where: { lower.contains($0) }) { return false }
        }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).count <= maxWords
    }

    /// Geschätzte Sprechdauer eines Texts: ~2,4 Wörter pro Sekunde, geklemmt
    /// auf 1,2–8 Sekunden. Die EINE Formel für alle Event-Quellen.
    static func estimatedDuration(for text: String) -> TimeInterval {
        let words = max(1, text.split(separator: " ").count)
        return min(8, max(1.2, Double(words) / 2.4))
    }
}
