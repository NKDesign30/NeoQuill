import XCTest
@testable import NeoQuill

final class FuseTranscriptsTests: XCTestCase {

    func testJaccardIdenticalSetsIsOne() {
        XCTAssertEqual(RecordingController.jaccard(["a", "b"], ["a", "b"]), 1)
    }

    func testJaccardDisjointSetsIsZero() {
        XCTAssertEqual(RecordingController.jaccard(["a", "b"], ["c", "d"]), 0)
    }

    func testJaccardPartialOverlap() {
        // |∩| = 1 (a), |∪| = 3 (a,b,c)
        XCTAssertEqual(RecordingController.jaccard(["a", "b"], ["a", "c"]), 1.0 / 3.0, accuracy: 0.0001)
    }

    func testLineTokensLowercasesAndSplitsOnPunctuation() {
        XCTAssertEqual(RecordingController.lineTokens("Hallo, Welt!"), ["hallo", "welt"])
    }

    func testEmptyOriginalReturnsIncoming() {
        let incoming = [line("das ist ein wichtiger satz")]
        XCTAssertEqual(RecordingController.fuseTranscripts(original: [], incoming: incoming).map(\.body), incoming.map(\.body))
    }

    func testEmptyIncomingReturnsOriginal() {
        let original = [line("das ist ein wichtiger satz")]
        XCTAssertEqual(RecordingController.fuseTranscripts(original: original, incoming: []).map(\.body), original.map(\.body))
    }

    func testIdenticalIncomingLineIsDeduped() {
        let original = [line("das ist ein wichtiger satz")]
        let incoming = [line("das ist ein wichtiger satz")]
        let fused = RecordingController.fuseTranscripts(original: original, incoming: incoming)
        XCTAssertEqual(fused.count, 1)
    }

    func testSubstantialGapLineIsInserted() {
        let original = [line("das ist ein wichtiger satz")]
        let incoming = [
            line("das ist ein wichtiger satz"),          // Dublette zum Original
            line("voellig anderer inhalt kommt dazu"),    // echte Luecke, >= 4 Tokens
        ]
        let fused = RecordingController.fuseTranscripts(original: original, incoming: incoming)
        XCTAssertEqual(fused.map(\.body), ["das ist ein wichtiger satz", "voellig anderer inhalt kommt dazu"])
    }

    func testShortUnmatchedLineIsSkipped() {
        let original = [line("das ist ein wichtiger satz")]
        let incoming = [line("ja genau")]   // nur 2 Tokens, < mergeMinTokens
        let fused = RecordingController.fuseTranscripts(original: original, incoming: incoming)
        XCTAssertEqual(fused.map(\.body), original.map(\.body))
    }

    private func line(_ body: String) -> TranscriptLine {
        TranscriptLine(who: "S1", timestamp: "00:00", body: body)
    }
}
