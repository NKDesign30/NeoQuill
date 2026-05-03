import XCTest
@testable import NeoQuill

final class CaptionDebugDumperTests: XCTestCase {
    func testSnapshotEncodesAndDecodesRoundtrip() throws {
        let snapshot = CaptionDebugSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
            accessibilityTrusted: false,
            apps: [
                AXAppDump(
                    bundleIdentifier: "com.microsoft.teams2",
                    processName: "Microsoft Teams",
                    capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
                    nodes: [
                        AXNodeDump(
                            role: "AXStaticText",
                            subrole: nil,
                            identifier: "caption-line",
                            title: nil,
                            value: "Sarah Ebner: Wir starten gleich.",
                            descriptionText: nil,
                            path: "app/AXWindow[0]/AXStaticText[3]",
                            depth: 4,
                            childCount: 0
                        )
                    ],
                    truncated: false
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CaptionDebugSnapshot.self, from: data)

        XCTAssertEqual(decoded.apps.count, 1)
        XCTAssertEqual(decoded.apps[0].nodes.first?.value, "Sarah Ebner: Wir starten gleich.")
        XCTAssertEqual(decoded.accessibilityTrusted, false)
    }

    @MainActor
    func testSnapshotMeetingAppsHandlesUntrustedAccessibilityGracefully() {
        let snapshot = CaptionDebugDumper.snapshotMeetingApps()
        XCTAssertNotNil(snapshot.capturedAt)
        if !snapshot.accessibilityTrusted {
            XCTAssertTrue(snapshot.apps.isEmpty, "Ohne AX-Trust dürfen keine Apps gedumpt werden.")
        }
    }

    @MainActor
    func testWriteSnapshotCreatesFileAndOverrideDirectoryRespected() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("neoquill-axdump-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let target = try CaptionDebugDumper.writeSnapshot(to: temp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "Snapshot-Datei muss existieren")
        XCTAssertEqual(target.deletingLastPathComponent().path, temp.path, "Override-Verzeichnis muss respektiert werden")

        let data = try Data(contentsOf: target)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CaptionDebugSnapshot.self, from: data)
        XCTAssertNotNil(snapshot.capturedAt)
    }

    func testNodeDumpHasUsefulContentChecksAllAttributes() {
        let empty = AXNodeDump(
            role: "AXGroup",
            subrole: nil,
            identifier: nil,
            title: nil,
            value: nil,
            descriptionText: nil,
            path: "app",
            depth: 0,
            childCount: 0
        )
        let withTitle = AXNodeDump(
            role: "AXButton",
            subrole: nil,
            identifier: nil,
            title: "Mute",
            value: nil,
            descriptionText: nil,
            path: "app",
            depth: 0,
            childCount: 0
        )
        XCTAssertFalse(empty.hasUsefulContent)
        XCTAssertTrue(withTitle.hasUsefulContent)
    }

    func testKnownBundleIdentifiersIncludeMeetingApps() {
        let bundleIds = CallApp.allKnownBundleIdentifiers
        XCTAssertTrue(bundleIds.contains("com.microsoft.teams2"))
        XCTAssertTrue(bundleIds.contains("us.zoom.xos"))
        XCTAssertTrue(bundleIds.contains("com.google.Chrome"))
        XCTAssertFalse(bundleIds.isEmpty)
    }
}
