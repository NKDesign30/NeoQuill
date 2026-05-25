import XCTest
@testable import NeoQuill

final class FirstLaunchMarkerTests: XCTestCase {
    private var marker: InMemoryFirstLaunchMarker!

    override func setUp() {
        super.setUp()
        marker = InMemoryFirstLaunchMarker()
    }

    func test_firstLaunchDate_isNil_whenNeverSet() {
        XCTAssertNil(marker.firstLaunchDate())
    }

    func test_ensureMarker_writesDate_onFirstCall() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        try marker.ensureMarker(now: now)
        XCTAssertEqual(marker.firstLaunchDate(), now)
    }

    func test_ensureMarker_isIdempotent_keepsOriginalDate() throws {
        let firstCall = Date(timeIntervalSince1970: 1_780_000_000)
        let secondCall = Date(timeIntervalSince1970: 1_790_000_000)

        try marker.ensureMarker(now: firstCall)
        try marker.ensureMarker(now: secondCall)

        XCTAssertEqual(marker.firstLaunchDate(), firstCall,
                       "Zweiter ensureMarker-Aufruf darf den ursprünglichen Marker nicht überschreiben.")
    }

    func test_reset_clearsMarker() throws {
        try marker.ensureMarker(now: Date())
        XCTAssertNotNil(marker.firstLaunchDate())
        marker.reset()
        XCTAssertNil(marker.firstLaunchDate())
    }

    func test_preExistingDate_isReturned() {
        let preset = Date(timeIntervalSince1970: 1_770_000_000)
        let preloaded = InMemoryFirstLaunchMarker(initialDate: preset)
        XCTAssertEqual(preloaded.firstLaunchDate(), preset)
    }

    /// Smoke-Test gegen die Keychain-Implementierung: wir erzeugen eine Instanz
    /// mit eigenem Service-Identifier-Pattern und prüfen das write→read→reset-Round-Trip.
    /// Wird nur lokal sinnvoll laufen (CI ohne Keychain überspringt).
    func test_keychainRoundtrip_smoke() throws {
        let real = KeychainFirstLaunchMarker()
        real.reset()
        defer { real.reset() }

        XCTAssertNil(real.firstLaunchDate())

        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try real.ensureMarker(now: now)

        let read = real.firstLaunchDate()
        XCTAssertNotNil(read)
        if let read {
            XCTAssertEqual(read.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1.0)
        }

        // Zweiter Aufruf darf nichts ändern
        try real.ensureMarker(now: now.addingTimeInterval(10_000))
        let readAgain = real.firstLaunchDate()
        if let read, let readAgain {
            XCTAssertEqual(readAgain.timeIntervalSince1970, read.timeIntervalSince1970, accuracy: 1.0)
        }
    }
}
