import XCTest
@testable import NeoQuill

final class CaptionFixtureReplayerTests: XCTestCase {

    func testReplayerYieldsAllSnapshotsInOrder() {
        let fixture = CaptionFixture(
            platform: .teams,
            snapshots: [
                CaptionFixturePollSnapshot(offsetSeconds: 0.0, candidates: [
                    CaptionFixtureCandidate(bundleIdentifier: "com.x", speakerName: "A", text: "Eins",
                                            rawText: nil, estimatedDuration: nil)
                ]),
                CaptionFixturePollSnapshot(offsetSeconds: 1.5, candidates: [
                    CaptionFixtureCandidate(bundleIdentifier: "com.x", speakerName: "B", text: "Zwei",
                                            rawText: nil, estimatedDuration: nil)
                ]),
            ]
        )

        var collected: [(TimeInterval, [String])] = []
        CaptionFixtureReplayer.replay(fixture) { offset, candidates in
            collected.append((offset, candidates.map(\.text)))
        }

        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0].0, 0.0)
        XCTAssertEqual(collected[0].1, ["Eins"])
        XCTAssertEqual(collected[1].0, 1.5)
        XCTAssertEqual(collected[1].1, ["Zwei"])
    }

    func testDefaultDurationGrowsWithWordCountButCaps() {
        XCTAssertEqual(CaptionFixtureReplayer.defaultDuration(for: "Ein Wort"), 0.9, accuracy: 0.001)
        XCTAssertEqual(CaptionFixtureReplayer.defaultDuration(for: "Vier Worte sind hier"), 1.8, accuracy: 0.001)
        let veryLong = Array(repeating: "Wort", count: 50).joined(separator: " ")
        XCTAssertEqual(CaptionFixtureReplayer.defaultDuration(for: veryLong), 12, accuracy: 0.001)
    }

    @MainActor
    func testCaptureServiceReplayDeduplicatesEchoedCaptions() {
        let service = CaptionCaptureService()
        let echoFixture = CaptionFixture(
            platform: .teams,
            snapshots: [
                CaptionFixturePollSnapshot(offsetSeconds: 1.0, candidates: [
                    CaptionFixtureCandidate(bundleIdentifier: "com.microsoft.teams2",
                                            speakerName: "Sarah Ebner",
                                            text: "Wir starten mit dem Pricing-Punkt.",
                                            rawText: "Sarah Ebner: Wir starten mit dem Pricing-Punkt.",
                                            estimatedDuration: 2.4)
                ]),
                CaptionFixturePollSnapshot(offsetSeconds: 1.8, candidates: [
                    CaptionFixtureCandidate(bundleIdentifier: "com.microsoft.teams2",
                                            speakerName: "Sarah Ebner",
                                            text: "Wir starten mit dem Pricing-Punkt.",
                                            rawText: "Sarah Ebner: Wir starten mit dem Pricing-Punkt.",
                                            estimatedDuration: 2.4)
                ]),
                CaptionFixturePollSnapshot(offsetSeconds: 4.1, candidates: [
                    CaptionFixtureCandidate(bundleIdentifier: "com.microsoft.teams2",
                                            speakerName: "Tom Friedrich",
                                            text: "Ich uebernehme den Rollout am Freitag.",
                                            rawText: "Tom Friedrich: Ich uebernehme den Rollout am Freitag.",
                                            estimatedDuration: 2.7)
                ]),
            ]
        )

        let events = service.replayFixture(echoFixture, startedAt: Date(timeIntervalSince1970: 1_770_000_000))

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].speakerName, "Sarah Ebner")
        XCTAssertEqual(events[1].speakerName, "Tom Friedrich")
    }

    @MainActor
    func testCaptureServiceReplayHandlesAnonymousCaptionWithLowerConfidence() {
        let service = CaptionCaptureService()
        let fixture = CaptionFixture(
            platform: .meet,
            snapshots: [
                CaptionFixturePollSnapshot(offsetSeconds: 0.5, candidates: [
                    CaptionFixtureCandidate(bundleIdentifier: "com.google.Chrome",
                                            speakerName: nil,
                                            text: "Klingt gut, machen wir so.",
                                            rawText: nil, estimatedDuration: nil)
                ]),
            ]
        )

        let events = service.replayFixture(fixture)
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?.speakerName)
        XCTAssertEqual(events.first?.confidence ?? 0, 0.45, accuracy: 0.001)
    }

    func testFixtureLoadsFromBundledJSON() throws {
        let url = Bundle.module.url(forResource: "teams-typical", withExtension: "json", subdirectory: "Fixtures/Captions")
        XCTAssertNotNil(url)
        let data = try Data(contentsOf: url!)
        let fixture = try CaptionFixture.loadJSON(data)
        XCTAssertEqual(fixture.platform, .teams)
        XCTAssertEqual(fixture.snapshots.count, 4)
    }
}
