import XCTest
@testable import NeoQuill

final class TranscriptWordAssemblerTests: XCTestCase {
    func testCombinesSubwordTokensAndAppliesChunkOffset() {
        let words = TranscriptWordAssembler.words(
            from: [
                TranscriptTokenSlice(text: "[_BEG_]", startMilliseconds: 0, endMilliseconds: 0, confidence: 1),
                TranscriptTokenSlice(text: " Das", startMilliseconds: 0, endMilliseconds: 300, confidence: 0.8),
                TranscriptTokenSlice(text: " Cl", startMilliseconds: 300, endMilliseconds: 500, confidence: 0.7),
                TranscriptTokenSlice(text: "ip", startMilliseconds: 500, endMilliseconds: 700, confidence: 0.9),
                TranscriptTokenSlice(text: ",", startMilliseconds: 700, endMilliseconds: 760, confidence: 0.6),
                TranscriptTokenSlice(text: " passt", startMilliseconds: 900, endMilliseconds: 1_100, confidence: 1),
            ],
            chunkOffsetMilliseconds: 83_000
        )

        XCTAssertEqual(words.map(\.text), ["Das", "Clip,", "passt"])
        XCTAssertEqual(words[0].startMilliseconds, 83_000)
        XCTAssertEqual(words[1].endMilliseconds, 83_760)
        XCTAssertEqual(try XCTUnwrap(words[1].confidence), 0.7333333333333333, accuracy: 0.0001)
    }
}
