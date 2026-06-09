import XCTest
@testable import NeoQuill

final class SpeakerPaletteTests: XCTestCase {

    func testLocalSpeakerUsesProfileColor() {
        XCTAssertEqual(SpeakerPalette.color(for: LocalSpeakerProfile.id), LocalSpeakerProfile.colorHex)
    }

    func testFixedSlotsKeepStableColors() {
        XCTAssertEqual(SpeakerPalette.color(for: "S1"), 0x7C8AFF)
        XCTAssertEqual(SpeakerPalette.color(for: "S2"), 0xFFB340)
        XCTAssertEqual(SpeakerPalette.color(for: "S3"), 0x409CFF)
        XCTAssertEqual(SpeakerPalette.color(for: "S4"), 0xD4845A)
    }

    func testUnknownIdIsDeterministic() {
        let first = SpeakerPalette.color(for: "EXT")
        let second = SpeakerPalette.color(for: "EXT")
        XCTAssertEqual(first, second)
    }

    func testUnknownIdStaysInPalette() {
        let palette: Set<UInt32> = [0x7C8AFF, 0xFFB340, 0x409CFF, 0xD4845A, 0xFF6259, 0x2EAB73]
        XCTAssertTrue(palette.contains(SpeakerPalette.color(for: "some-unknown-speaker")))
    }

    func testFixedSpeakerIdsAreS1ToS4() {
        XCTAssertEqual(SpeakerPalette.fixedSpeakerIds, ["S1", "S2", "S3", "S4"])
    }
}
