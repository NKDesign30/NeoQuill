import XCTest
@testable import NeoQuill

final class AppVersionInfoTests: XCTestCase {
    func testBuildsVersionInfoFromBundleDictionary() {
        let info = AppVersionInfo.from(info: [
            "CFBundleShortVersionString": "0.9.0",
            "CFBundleVersion": "42",
            "NeoQuillGitCommit": "abc1234",
            "NeoQuillGitBranch": "dev",
            "NeoQuillGitDirty": "dirty",
            "NeoQuillBuildDate": "2026-05-24T09:30:00Z",
        ])

        XCTAssertEqual(info.displayVersion, "v0.9.0 (42)")
        XCTAssertEqual(info.displayGit, "dev@abc1234 dirty")
        XCTAssertEqual(info.buildDate, "2026-05-24T09:30:00Z")
    }

    func testUsesStableFallbacksForMissingMetadata() {
        let info = AppVersionInfo.from(info: [:])

        XCTAssertEqual(info.version, "0.0.0")
        XCTAssertEqual(info.build, "0")
        XCTAssertEqual(info.gitCommit, "unknown")
        XCTAssertEqual(info.gitBranch, "unknown")
        XCTAssertEqual(info.gitDirty, "unknown")
    }
}
