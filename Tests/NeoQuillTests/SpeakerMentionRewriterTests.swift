import XCTest
@testable import NeoQuill

final class SpeakerMentionRewriterTests: XCTestCase {

    func testReplacesIdMentionAsWholeWord() {
        let out = SpeakerMentionRewriter.rewrite(in: "S2 fragt nach.", oldId: "S2", oldName: nil, newName: "Thorsten")
        XCTAssertEqual(out, "Thorsten fragt nach.")
    }

    func testReplacesSpokenLabelForm() {
        let out = SpeakerMentionRewriter.rewrite(in: "Speaker 2 stimmt zu.", oldId: "S2", oldName: nil, newName: "Thorsten")
        XCTAssertEqual(out, "Thorsten stimmt zu.")
    }

    func testReplacesOldName() {
        let out = SpeakerMentionRewriter.rewrite(in: "Gast meldet sich.", oldId: "S3", oldName: "Gast", newName: "Nadja")
        XCTAssertEqual(out, "Nadja meldet sich.")
    }

    func testDoesNotReplaceInsideLongerWord() {
        // "S2" darf nicht in "S20" oder "AS2DF" getroffen werden.
        let out = SpeakerMentionRewriter.rewrite(in: "S20 und AS2DF", oldId: "S2", oldName: nil, newName: "X")
        XCTAssertEqual(out, "S20 und AS2DF")
    }

    func testCandidatesAreLongestFirstAndDeduped() {
        let candidates = SpeakerMentionRewriter.candidates(oldId: "S2", oldName: "S2")
        // "Speaker S2" (10) und "Speaker 2" (9) vor "S2" (2); "S2" nur einmal trotz oldName == oldId.
        XCTAssertEqual(candidates.first, "Speaker S2")
        XCTAssertEqual(candidates.filter { $0 == "S2" }.count, 1)
    }

    func testWholeMentionEscapesRegexMetacharacters() {
        let out = SpeakerMentionRewriter.replacingWholeMention("S.2", in: "S.2 spricht", with: "Y")
        XCTAssertEqual(out, "Y spricht")
    }
}
