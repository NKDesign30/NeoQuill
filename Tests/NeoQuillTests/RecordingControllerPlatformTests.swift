import XCTest
@testable import NeoQuill

/// Pinnt das CallApp→Platform-Mapping fest, das beim `start()` in die
/// `CapturedSession` eingefroren wird. Historischer Bug: die Plattform wurde
/// zur Persist-Zeit aus dem Detector gelesen, der beim Call-Ende bereits auf
/// `.unknown` resettet war — auto-gestoppte Teams/Zoom-Meetings landeten als
/// `.call` in der Datenbank.
final class RecordingControllerPlatformTests: XCTestCase {

    func testMappedPlatformForDedicatedApps() {
        XCTAssertEqual(RecordingController.mappedPlatform(from: .teams), .teams)
        XCTAssertEqual(RecordingController.mappedPlatform(from: .zoom), .zoom)
        XCTAssertEqual(RecordingController.mappedPlatform(from: .browser), .meet)
    }

    func testMappedPlatformFallsBackToGenericCall() {
        XCTAssertEqual(RecordingController.mappedPlatform(from: .facetime), .call)
        XCTAssertEqual(RecordingController.mappedPlatform(from: .slack), .call)
        XCTAssertEqual(RecordingController.mappedPlatform(from: .discord), .call)
        XCTAssertEqual(RecordingController.mappedPlatform(from: .webex), .call)
        XCTAssertEqual(RecordingController.mappedPlatform(from: .unknown), .call)
    }
}
