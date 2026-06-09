import XCTest
@testable import NeoQuill

final class SpeakerIdentityCoordinatorTests: XCTestCase {

    typealias Kind = SpeakerIdentityCoordinator.IdentityKind

    func testCaptionKindMapsToCaptionSourceWithoutExternalId() {
        XCTAssertEqual(Kind.caption.lineSource, .caption)
        XCTAssertEqual(Kind.caption.aliasSource, "caption")
        XCTAssertNil(Kind.caption.externalId(for: "S2"))
    }

    func testPlatformKindMapsToPlatformApiWithWhoAsExternalId() {
        XCTAssertEqual(Kind.platform.lineSource, .platformApi)
        XCTAssertEqual(Kind.platform.aliasSource, "platform")
        XCTAssertEqual(Kind.platform.externalId(for: "S2"), "S2")
    }

    func testKnownSpeakerIdWins() {
        let id = SpeakerIdentityCoordinator.canonicalId(name: "Niko", knownSpeakerId: "speaker-fixed")
        XCTAssertEqual(id, "speaker-fixed")
    }

    func testGeneratesSlugFromName() {
        XCTAssertEqual(SpeakerIdentityCoordinator.canonicalId(name: "Jörg Müller"), "speaker-jorg-muller")
    }

    func testEmptyNameFallsBackToUnknownSlug() {
        XCTAssertEqual(SpeakerIdentityCoordinator.canonicalId(name: "   "), "speaker-unknown")
    }
}
