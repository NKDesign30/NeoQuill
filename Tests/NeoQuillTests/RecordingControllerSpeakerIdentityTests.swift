import XCTest
@testable import NeoQuill

final class RecordingControllerSpeakerIdentityTests: XCTestCase {
    @MainActor
    func testKnownSpeakerIdWinsOverInitials() {
        let id = RecordingController.canonicalSpeakerId(
            name: "Thorsten Fischer",
            knownSpeakerId: "speaker-thorsten-2026"
        )

        XCTAssertEqual(id, "speaker-thorsten-2026")
    }

    @MainActor
    func testBlankKnownSpeakerIdFallsBackToInitials() {
        let id = RecordingController.canonicalSpeakerId(
            name: "Thorsten Fischer",
            knownSpeakerId: "   "
        )

        XCTAssertEqual(id, "TF")
    }

    @MainActor
    func testSingleNameFallsBackToFirstInitial() {
        let id = RecordingController.canonicalSpeakerId(name: "Niko")

        XCTAssertEqual(id, "N")
    }
}
