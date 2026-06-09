import XCTest
@testable import NeoQuill

final class SystemAudioSourceTests: XCTestCase {

    /// Ein Adapter, der den Vertrag erfüllt und beim Start seine Sample-Callbacks
    /// feuert — stellvertretend für ProcessAudioTap/SCKAudioCapture.
    private final class FakeSystemAudioSource: SystemAudioSource {
        var onSamples: (([Float]) -> Void)?
        var onSamplesHQ: (([Float]) -> Void)?
        private(set) var startedWith: [String]?
        private(set) var stopped = false

        func start(bundleIdentifiers: [String]) async throws {
            startedWith = bundleIdentifiers
            onSamples?([0.1, 0.2, 0.3])
            onSamplesHQ?([0.4, 0.5])
        }

        func stop() async { stopped = true }
    }

    func testCallbackContractIsPolymorphic() async throws {
        let source: SystemAudioSource = FakeSystemAudioSource()
        var asrSamples: [Float] = []
        var hqSamples: [Float] = []
        source.onSamples = { asrSamples.append(contentsOf: $0) }
        source.onSamplesHQ = { hqSamples.append(contentsOf: $0) }

        try await source.start(bundleIdentifiers: ["com.test.app"])

        XCTAssertEqual(asrSamples, [0.1, 0.2, 0.3])
        XCTAssertEqual(hqSamples, [0.4, 0.5])
    }

    func testStartAndStopThroughProtocol() async throws {
        let fake = FakeSystemAudioSource()
        let source: SystemAudioSource = fake

        try await source.start(bundleIdentifiers: ["a", "b"])
        await source.stop()

        XCTAssertEqual(fake.startedWith, ["a", "b"])
        XCTAssertTrue(fake.stopped)
    }

    /// Sichert ab, dass die synchronen `ProcessAudioTap`-Methoden den asynchronen
    /// Protokoll-Vertrag erfüllen (Witness-Auflösung, rein zur Compile-Zeit).
    func testProcessAudioTapConformsToContract() {
        let source: SystemAudioSource = ProcessAudioTap()
        XCTAssertNil(source.onSamples)
    }
}
