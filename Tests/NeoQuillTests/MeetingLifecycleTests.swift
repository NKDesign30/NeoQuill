import XCTest
@testable import NeoQuill

final class MeetingLifecycleTests: XCTestCase {

    func testSerializationRoundtrip() {
        let cases: [MeetingLifecycle] = [
            .recording, .transcribing, .summarizing, .done,
            .failed(reason: "Mehrfach unterbrochen", attempts: 3),
        ]
        for value in cases {
            XCTAssertEqual(MeetingLifecycle(serialized: value.serialized), value)
        }
    }

    /// Der Grund darf Doppelpunkte enthalten — nur der erste Trenner zählt.
    func testFailedReasonWithColonsSurvivesRoundtrip() {
        let value = MeetingLifecycle.failed(reason: "Fehler: a:b:c", attempts: 2)
        XCTAssertEqual(MeetingLifecycle(serialized: value.serialized), value)
    }

    /// Unbekannte/leere Werte (z.B. korrupte Spalte) dürfen nicht busy hängen.
    func testUnknownSerializedDefaultsToDone() {
        XCTAssertEqual(MeetingLifecycle(serialized: "garbage"), .done)
        XCTAssertEqual(MeetingLifecycle(serialized: ""), .done)
        XCTAssertEqual(MeetingLifecycle(serialized: "failed:notanumber"), .failed(reason: "", attempts: 0))
    }

    func testIsBusy() {
        XCTAssertTrue(MeetingLifecycle.recording.isBusy)
        XCTAssertTrue(MeetingLifecycle.transcribing.isBusy)
        XCTAssertTrue(MeetingLifecycle.summarizing.isBusy)
        XCTAssertFalse(MeetingLifecycle.done.isBusy)
        XCTAssertFalse(MeetingLifecycle.failed(reason: "x", attempts: 1).isBusy)
    }
}
