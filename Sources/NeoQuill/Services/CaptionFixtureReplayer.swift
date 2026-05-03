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
    /// Aufrufers (typischerweise CaptionCaptureService.injectFixtureSnapshot).
    static func replay(
        _ fixture: CaptionFixture,
        consume: (TimeInterval, [CaptionCandidate]) -> Void
    ) {
        for snapshot in fixture.snapshots {
            let candidates = snapshot.candidates.map { $0.toCandidate() }
            consume(snapshot.offsetSeconds, candidates)
        }
    }

    /// Wenn die Fixture keine Dauer mitliefert, schaetzen wir aus der Wortzahl
    /// (analog CaptionTextParser).
    static func defaultDuration(for text: String) -> TimeInterval {
        let words = max(1, text.split(separator: " ").count)
        return min(TimeInterval(words) * 0.45, 12)
    }
}
