import XCTest
import Foundation
@testable import NeoQuill

final class AudioIngestServiceTests: XCTestCase {

    /// Echter Pfad: eine vom AudioWriter geschriebene WAV wird wieder zu Samples
    /// dekodiert. Sichert ab, dass der Security-Scope-Wrapper das Dekodieren
    /// nicht bricht.
    func testDecodesPersistedWavRoundTrip() async throws {
        let id = "ingest-test-\(UUID().uuidString)"
        let samples = (0..<16_000).map { Float(sin(Double($0) * 0.05)) }
        let url = try XCTUnwrap(AudioWriter.persist(id: id, stem: .mix, samples: samples))
        defer { try? FileManager.default.removeItem(at: url) }

        let decoded = try await AudioIngestService.decode(url: url)

        XCTAssertFalse(decoded.isEmpty)
        XCTAssertGreaterThan(decoded.count, 8_000)
    }

    func testThrowsForUnreadableFile() async {
        let bogus = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).wav")
        do {
            _ = try await AudioIngestService.decode(url: bogus)
            XCTFail("Erwartet: Fehler beim Dekodieren einer fehlenden Datei")
        } catch {
            // erwartet
        }
    }
}
