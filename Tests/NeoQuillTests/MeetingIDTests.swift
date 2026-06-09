import XCTest
@testable import NeoQuill

/// Sichert den Producer/Parser-Kontrakt des Meeting-ID-Formats, der vorher als
/// nackter String-Prefix zwischen RecordingController und
/// TranscriptDownloadWatcher verteilt war.
final class MeetingIDTests: XCTestCase {
    func testRecordingProducesRecPrefixedUnixTimestamp() {
        let date = Date(timeIntervalSince1970: 1_714_742_400)
        XCTAssertEqual(MeetingID.recording(at: date), "rec-1714742400")
    }

    func testImportedProducesImportPrefixedUnixTimestamp() {
        let date = Date(timeIntervalSince1970: 1_714_742_400)
        XCTAssertEqual(MeetingID.imported(at: date), "import-1714742400")
    }

    func testRecordingStartParsesRecPrefixedId() {
        XCTAssertEqual(MeetingID.recordingStart(from: "rec-1714742400"), 1_714_742_400)
    }

    func testRecordingStartAcceptsBareTimestamp() {
        XCTAssertEqual(MeetingID.recordingStart(from: "1714742400"), 1_714_742_400)
    }

    func testRecordingStartRejectsImportedAndManualIds() {
        // Importierte Meetings werden bewusst nicht im Zeitfenster gematcht.
        XCTAssertNil(MeetingID.recordingStart(from: "import-1714742400"))
        XCTAssertNil(MeetingID.recordingStart(from: "manual-meeting"))
        XCTAssertNil(MeetingID.recordingStart(from: "rec-not-a-number"))
    }

    func testRecordingRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let id = MeetingID.recording(at: date)
        XCTAssertEqual(MeetingID.recordingStart(from: id), 1_700_000_000)
    }
}
