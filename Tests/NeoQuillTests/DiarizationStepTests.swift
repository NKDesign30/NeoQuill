import XCTest
@testable import NeoQuill

final class DiarizationStepTests: XCTestCase {

    // MARK: - Gate

    func testGateRequiresAllThreeConditions() {
        let enough = DiarizationStep.minimumSampleCount + 1
        XCTAssertTrue(DiarizationStep.shouldRun(enabled: true, diarizerReady: true, sampleCount: enough))
        XCTAssertFalse(DiarizationStep.shouldRun(enabled: false, diarizerReady: true, sampleCount: enough),
                       "Deaktiviertes Setting muss das Gate schließen")
        XCTAssertFalse(DiarizationStep.shouldRun(enabled: true, diarizerReady: false, sampleCount: enough),
                       "Nicht vorbereiteter Diarizer muss das Gate schließen")
        XCTAssertFalse(DiarizationStep.shouldRun(enabled: true, diarizerReady: true, sampleCount: 0))
    }

    func testGateIsStrictlyGreaterThanFiveSeconds() {
        XCTAssertFalse(DiarizationStep.shouldRun(
            enabled: true, diarizerReady: true,
            sampleCount: DiarizationStep.minimumSampleCount
        ), "Exakt 5 Sekunden reichen nicht — das Gate ist strikt größer")
        XCTAssertTrue(DiarizationStep.shouldRun(
            enabled: true, diarizerReady: true,
            sampleCount: DiarizationStep.minimumSampleCount + 1
        ))
    }

    // MARK: - Embedding-Sammlung

    func testCollectEmbeddingsTakesFirstSegmentPerSpeaker() {
        let segments = [
            DiarizedSpeakerSegment(start: 0, end: 2, speakerId: "S1", embedding: [1, 0]),
            DiarizedSpeakerSegment(start: 2, end: 4, speakerId: "S2", embedding: [0, 1]),
            DiarizedSpeakerSegment(start: 4, end: 6, speakerId: "S1", embedding: [9, 9]),
        ]
        let embeddings = DiarizationStep.collectEmbeddings(from: segments)
        XCTAssertEqual(embeddings["S1"], [1, 0], "Das erste Segment eines Sprechers gewinnt")
        XCTAssertEqual(embeddings["S2"], [0, 1])
        XCTAssertEqual(embeddings.count, 2)
    }

    func testCollectEmbeddingsKeepsFirstEvenIfEmpty() {
        // Bewusster Kontrakt: leere Embeddings blocken spätere desselben
        // Sprechers — die Konsumenten filtern Leere selbst.
        let segments = [
            DiarizedSpeakerSegment(start: 0, end: 2, speakerId: "S1", embedding: []),
            DiarizedSpeakerSegment(start: 2, end: 4, speakerId: "S1", embedding: [1, 2]),
        ]
        let embeddings = DiarizationStep.collectEmbeddings(from: segments)
        XCTAssertEqual(embeddings["S1"], [])
    }

    func testCollectEmbeddingsEmptyInput() {
        XCTAssertTrue(DiarizationStep.collectEmbeddings(from: []).isEmpty)
    }
}
