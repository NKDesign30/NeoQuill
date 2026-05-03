import XCTest
@testable import NeoQuill

final class CaptionTextParserTests: XCTestCase {
    func testParsesColonSpeakerCaption() {
        let candidate = CaptionTextParser.parseCandidate(
            "Sarah Ebner: Wir brauchen die Freigabe bis Freitag.",
            bundleIdentifier: "com.microsoft.teams2"
        )

        XCTAssertEqual(candidate?.speakerName, "Sarah Ebner")
        XCTAssertEqual(candidate?.text, "Wir brauchen die Freigabe bis Freitag.")
        XCTAssertEqual(candidate?.bundleIdentifier, "com.microsoft.teams2")
    }

    func testParsesMultilineSpeakerCaption() {
        let candidate = CaptionTextParser.parseCandidate(
            "Thomas Müller\nIch prüfe das Lizenzmodell.",
            bundleIdentifier: "com.google.Chrome"
        )

        XCTAssertEqual(candidate?.speakerName, "Thomas Müller")
        XCTAssertEqual(candidate?.text, "Ich prüfe das Lizenzmodell.")
    }

    func testFiltersMeetingChromeControls() {
        XCTAssertFalse(CaptionTextParser.isUsefulVisibleText("Share screen"))
        XCTAssertFalse(CaptionTextParser.isUsefulVisibleText("Mikrofon stummschalten"))
        XCTAssertTrue(CaptionTextParser.isUsefulVisibleText("Wir sollten nächste Woche starten."))
    }

    func testFingerprintDedupesWhitespaceAndPunctuation() throws {
        let first = try XCTUnwrap(CaptionTextParser.parseCandidate(
            "Sarah Ebner: Wir starten jetzt.",
            bundleIdentifier: nil
        ))
        let second = try XCTUnwrap(CaptionTextParser.parseCandidate(
            " Sarah Ebner :   Wir starten jetzt! ",
            bundleIdentifier: nil
        ))

        XCTAssertEqual(
            CaptionTextParser.fingerprint(candidate: first, platform: .teams),
            CaptionTextParser.fingerprint(candidate: second, platform: .teams)
        )
    }
}
