import XCTest
@testable import NeoQuill

final class LocTests: XCTestCase {
    func testForcedLanguageReadsMatchingBundle() {
        XCTAssertEqual(Loc.string("test.probe", lang: "de"), "Lokalisierung funktioniert")
        XCTAssertEqual(Loc.string("test.probe", lang: "en"), "Localization works")
    }

    func testUnknownKeyFallsBackToKey() {
        XCTAssertEqual(Loc.string("nonexistent.key.xyz", lang: "en"), "nonexistent.key.xyz")
    }

    func testSystemLanguageResolvesFromModuleBundle() {
        // "system" -> defaultLocalization (de). Beweist, dass Bundle.module die
        // Lokalisierung trägt, ohne eine konkrete Sprache zu erzwingen.
        XCTAssertEqual(Loc.string("test.probe", lang: "system"), "Lokalisierung funktioniert")
    }
}
