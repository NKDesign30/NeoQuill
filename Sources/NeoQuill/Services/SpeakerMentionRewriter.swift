import Foundation

/// Ersetzt Sprecher-Erwähnungen in zusammengefasstem Text, wenn ein Sprecher
/// umbenannt wird — etwa „S2" / „Speaker 2" / der alte Name → „Morgan" in
/// TL;DR, Highlights, Tasks und Kapiteln.
///
/// Vorher lag diese reine String-Logik privat in `MeetingStore` und war damit nur
/// über die SQLite-Klasse erreichbar — also faktisch nicht testbar, obwohl sie
/// keinerlei DB-Bezug hat. Hier ist sie ein eigenständiges, testbares Modul.
enum SpeakerMentionRewriter {
    /// Ersetzt alle Erwähnungen eines Sprechers (per alter ID oder altem Namen)
    /// im Text durch den neuen Namen. Längere Kandidaten zuerst, jeweils nur als
    /// ganzes Wort.
    static func rewrite(in text: String, oldId: String, oldName: String?, newName: String) -> String {
        candidates(oldId: oldId, oldName: oldName).reduce(text) { partial, candidate in
            replacingWholeMention(candidate, in: partial, with: newName)
        }
    }

    /// Die Such-Kandidaten für einen Sprecher: alter Name, ID, „Speaker <id>" und
    /// „Speaker <nummer>" — getrimmt, dedupliziert, längste zuerst (damit
    /// „Speaker 2" vor „2" greift). Internal für Tests.
    static func candidates(oldId: String, oldName: String?) -> [String] {
        var candidates = [oldName, oldId, "Speaker \(oldId)"]
        let upperId = oldId.uppercased()
        if upperId.hasPrefix("S") {
            let number = String(upperId.dropFirst())
            if !number.isEmpty {
                candidates.append("Speaker \(number)")
            }
        }

        var seen: Set<String> = []
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .filter { seen.insert($0).inserted }
    }

    /// Ersetzt `candidate` im Text nur als ganzes Wort (keine Treffer mitten in
    /// einem längeren Token). Internal für Tests.
    static func replacingWholeMention(_ candidate: String, in text: String, with replacement: String) -> String {
        let pattern = "(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: candidate))(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
