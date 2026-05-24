import XCTest
@testable import NeoQuill

final class RecordingControllerSpeakerIdentityTests: XCTestCase {
    @MainActor
    func testKnownSpeakerIdWinsOverGeneratedSlug() {
        let id = RecordingController.canonicalSpeakerId(
            name: "Thorsten Fischer",
            knownSpeakerId: "speaker-thorsten-2026"
        )

        XCTAssertEqual(id, "speaker-thorsten-2026")
    }

    @MainActor
    func testExistingSpeakerNameReusesLegacyIdentity() {
        let existing = labeledSpeaker(id: "TF", name: "Thorsten Fischer")
        let id = RecordingController.canonicalSpeakerId(
            name: " thorsten   fischer ",
            knownSpeakerId: "   ",
            existingSpeakers: [existing]
        )

        XCTAssertEqual(id, "TF")
    }

    @MainActor
    func testNewMultiWordSpeakerUsesStableNameSlug() {
        let id = RecordingController.canonicalSpeakerId(
            name: "Thorsten Fischer",
            knownSpeakerId: "   "
        )

        XCTAssertEqual(id, "speaker-thorsten-fischer")
    }

    @MainActor
    func testSingleNamesDoNotCollideByInitial() {
        let nikoId = RecordingController.canonicalSpeakerId(name: "Niko")
        let nadjaId = RecordingController.canonicalSpeakerId(name: "Nadja")

        XCTAssertEqual(nikoId, "speaker-niko")
        XCTAssertEqual(nadjaId, "speaker-nadja")
        XCTAssertNotEqual(nikoId, nadjaId)
    }

    @MainActor
    func testGeneratedSpeakerIdNormalizesDiacritics() {
        let id = RecordingController.canonicalSpeakerId(name: "Jörg Müller")

        XCTAssertEqual(id, "speaker-jorg-muller")
    }

    private func labeledSpeaker(id: String, name: String) -> LabeledSpeaker {
        LabeledSpeaker(
            id: id,
            name: name,
            embedding: [],
            colorHex: 0x2EAB73,
            createdAt: Date(timeIntervalSince1970: 0),
            lastSeenAt: Date(timeIntervalSince1970: 0)
        )
    }
}
