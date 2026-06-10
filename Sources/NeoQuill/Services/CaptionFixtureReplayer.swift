import Foundation

// Test/QA Replayer für Caption-Pollings. Bildet einen synthetischen AX-Stream
// nach (was extractCaptionCandidates pro Poll liefern würde) und feuert ihn
// in dieselbe Pipeline wie das Live-Polling. Damit lassen sich Echo-Dedupe,
// Speaker-Splits und Edge-Cases (Caption ohne Speaker, Hidden-Identity) ohne
// laufende Teams/Meet/Zoom-Session reproduzierbar testen.

struct CaptionFixturePollSnapshot: Codable, Hashable {
    /// Sekunden seit Meeting-Start, an denen der Snapshot beobachtet wird.
    let offsetSeconds: TimeInterval
    let candidates: [CaptionFixtureCandidate]
}

struct CaptionFixtureCandidate: Codable, Hashable {
    let bundleIdentifier: String?
    let speakerName: String?
    let text: String
    let rawText: String?
    let estimatedDuration: TimeInterval?

    func toCandidate() -> CaptionCandidate {
        CaptionCandidate(
            bundleIdentifier: bundleIdentifier,
            speakerName: speakerName,
            text: text,
            rawText: rawText ?? text,
            estimatedDuration: estimatedDuration ?? CaptionFixtureReplayer.defaultDuration(for: text)
        )
    }
}

struct CaptionFixture: Codable, Hashable {
    let platform: Platform
    let snapshots: [CaptionFixturePollSnapshot]

    static func loadJSON(_ data: Data) throws -> CaptionFixture {
        try JSONDecoder().decode(CaptionFixture.self, from: data)
    }
}

enum CaptionFixtureReplayer {

    /// Spielt eine Fixture deterministisch durch: pro Snapshot werden alle
    /// Candidates an `consume` weitergereicht — analog zum Live-Polling.
    /// Dedupe + Echo-Filter laufen identisch in der `consume`-Closure des
    /// Aufrufers (typischerweise CaptionCaptureService.replayFixture).
    static func replay(
        _ fixture: CaptionFixture,
        consume: (TimeInterval, [CaptionCandidate]) -> Void
    ) {
        for snapshot in fixture.snapshots {
            let candidates = snapshot.candidates.map { $0.toCandidate() }
            consume(snapshot.offsetSeconds, candidates)
        }
    }

    /// Wenn die Fixture keine Dauer mitliefert: dieselbe Formel wie alle
    /// Event-Quellen. Vorher rechnete dieser Pfad words×0.45 statt words/2.4 —
    /// der Kommentar behauptete "analog CaptionTextParser", die Zahlen drifteten.
    static func defaultDuration(for text: String) -> TimeInterval {
        TranscriptEventHeuristics.estimatedDuration(for: text)
    }
}
