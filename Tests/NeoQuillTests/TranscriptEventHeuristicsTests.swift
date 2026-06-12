import XCTest
@testable import NeoQuill

final class TranscriptEventHeuristicsTests: XCTestCase {

    // MARK: - isProbableSpeakerName

    func testAcceptsTypicalNames() {
        XCTAssertTrue(TranscriptEventHeuristics.isProbableSpeakerName("Sarah Ebner"))
        XCTAssertTrue(TranscriptEventHeuristics.isProbableSpeakerName("Dr. Jörg Müller-Lüdenscheidt"))
    }

    func testRejectsTooShortTooLongAndLetterless() {
        XCTAssertFalse(TranscriptEventHeuristics.isProbableSpeakerName("A"))
        XCTAssertFalse(TranscriptEventHeuristics.isProbableSpeakerName(String(repeating: "x", count: 65)))
        XCTAssertFalse(TranscriptEventHeuristics.isProbableSpeakerName("12:34"))
    }

    func testWordLimitIsConfigurablePerSource() {
        let six = "Anna Berta Carla Dora Emma Frieda"
        XCTAssertFalse(TranscriptEventHeuristics.isProbableSpeakerName(six),
                       "Default-Profil (AX/JSON) erlaubt höchstens 5 Wörter")
        XCTAssertTrue(TranscriptEventHeuristics.isProbableSpeakerName(six, maxWords: 6),
                      "VTT-Profil erlaubt 6 Wörter")
    }

    func testVTTProfileAcceptsSingleLetterSpeaker() {
        XCTAssertTrue(TranscriptEventHeuristics.isProbableSpeakerName("A", minLength: 1, maxWords: 6),
                      "Anonymisierte VTT-Cues nutzen 1-Zeichen-Speaker")
    }

    func testBlockedFragmentsFilterUIWords() {
        XCTAssertFalse(TranscriptEventHeuristics.isProbableSpeakerName(
            "Live-Untertitel", blockedFragments: ["caption", "untertitel", "transcript"]
        ))
        XCTAssertTrue(TranscriptEventHeuristics.isProbableSpeakerName(
            "Alex", blockedFragments: ["caption", "untertitel", "transcript"]
        ))
    }

    // MARK: - estimatedDuration (die EINE Formel)

    func testEstimatedDurationClampsBetweenFloorAndCap() {
        XCTAssertEqual(TranscriptEventHeuristics.estimatedDuration(for: "Hi"), 1.2, accuracy: 0.001)
        XCTAssertEqual(
            TranscriptEventHeuristics.estimatedDuration(for: "eins zwei drei vier fünf sechs"),
            6.0 / 2.4,
            accuracy: 0.001
        )
        let long = Array(repeating: "Wort", count: 40).joined(separator: " ")
        XCTAssertEqual(TranscriptEventHeuristics.estimatedDuration(for: long), 8, accuracy: 0.001)
    }
}
