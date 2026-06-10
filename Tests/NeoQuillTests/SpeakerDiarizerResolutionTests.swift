import XCTest
@testable import NeoQuill

/// Pinnt die Diarization-Resolution-Regeln fest, die vorher als private
/// RecordingController-Methoden nur mit echten FluidAudio-Modellen erreichbar
/// waren: Kurz-Segment-Filter, Known-Voice-Vorrang, ID-Normalisierung.
final class SpeakerDiarizerResolutionTests: XCTestCase {

    private let noMatch: ([Float]) -> (id: String, score: Float)? = { _ in nil }

    // MARK: - Kurz-Segment-Filter

    func testSegmentBelowMinDurationIsDropped() {
        let segment = SpeakerDiarizer.resolveSegment(
            start: 5.0, end: 6.1, rawSpeakerId: "0", embedding: [0.1], matcher: noMatch
        )
        XCTAssertNil(segment, "1.1s liegt unter der 1.2s-Schwelle")
    }

    func testSegmentExactlyAtMinDurationIsKept() {
        let segment = SpeakerDiarizer.resolveSegment(
            start: 5.0, end: 6.2, rawSpeakerId: "0", embedding: [0.1], matcher: noMatch
        )
        XCTAssertNotNil(segment)
    }

    // MARK: - Known-Voice vs. anonym

    func testKnownVoiceMatchWinsAndCarriesScore() {
        let segment = SpeakerDiarizer.resolveSegment(
            start: 0, end: 4, rawSpeakerId: "0", embedding: [0.5, 0.5],
            matcher: { _ in ("speaker-thorsten", 0.91) }
        )
        XCTAssertEqual(segment?.speakerId, "speaker-thorsten")
        XCTAssertEqual(segment?.speakerSource, .knownVoice)
        XCTAssertEqual(segment?.confidence ?? 0, 0.91, accuracy: 0.0001)
    }

    func testUnmatchedSegmentFallsBackToNormalizedAnonymousId() {
        let segment = SpeakerDiarizer.resolveSegment(
            start: 0, end: 4, rawSpeakerId: "1", embedding: [0.5], matcher: noMatch
        )
        XCTAssertEqual(segment?.speakerId, "S2", "FluidAudio zählt ab 0 — UI ab S1")
        XCTAssertEqual(segment?.speakerSource, .diarization)
        XCTAssertEqual(segment?.confidence ?? 0, SpeakerDiarizer.anonymousConfidence, accuracy: 0.0001)
    }

    // MARK: - displaySpeakerId-Normalisierung

    func testDisplaySpeakerIdNormalizesAllKnownShapes() {
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: ""), "S1")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "  "), "S1")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "S2"), "S2")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "s3"), "S3")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "0"), "S1")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "2"), "S3")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "Speaker 1"), "S2")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "spk3"), "S4")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "AB"), "AB")
        XCTAssertEqual(SpeakerDiarizer.displaySpeakerId(for: "completely-unknown"), "S1")
    }
}
