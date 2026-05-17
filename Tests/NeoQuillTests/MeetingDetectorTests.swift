import XCTest
@testable import NeoQuill

final class MeetingDetectorTests: XCTestCase {
    func testBrowserOutputOnlyDoesNotTriggerCallDetection() {
        let app = MeetingDetector.detectRunningCallAudioProcess(from: [
            AudioProcessActivity(
                bundleIdentifier: "com.google.Chrome",
                isRunningInput: false,
                isRunningOutput: true,
                isRunning: true
            ),
        ])

        XCTAssertNil(app)
    }

    func testBrowserInputStillTriggersBrowserCallDetection() {
        let app = MeetingDetector.detectRunningCallAudioProcess(from: [
            AudioProcessActivity(
                bundleIdentifier: "com.google.Chrome",
                isRunningInput: true,
                isRunningOutput: true,
                isRunning: true
            ),
        ])

        XCTAssertEqual(app, .browser)
    }

    func testTeamsOutputStillTriggersCallDetection() {
        let app = MeetingDetector.detectRunningCallAudioProcess(from: [
            AudioProcessActivity(
                bundleIdentifier: "com.microsoft.teams2",
                isRunningInput: false,
                isRunningOutput: true,
                isRunning: true
            ),
        ])

        XCTAssertEqual(app, .teams)
    }
}
