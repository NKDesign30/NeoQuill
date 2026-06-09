import XCTest
@testable import NeoQuill

final class MeetingDetailWithTests: XCTestCase {

    private func sample() -> MeetingDetail {
        MeetingDetail(
            id: "m1", title: "Titel", dateLong: "Montag, 09. Juni", timeRange: "14:00 – 14:30",
            duration: "30m", platform: .call, wordCount: 100,
            participants: [Participant(id: "S1", name: "A", role: "Erkannt", colorHex: 0x111111, spoke: "10m")],
            tldr: "alt", highlights: [], tasks: [], chapters: [],
            transcript: [], audioURL: "/tmp/a.wav", lifecycle: .summarizing
        )
    }

    func testNoArgsReturnsEqualValue() {
        let d = sample()
        XCTAssertEqual(d.with(), d)
    }

    func testChangesOnlyTheGivenField() {
        let d = sample()
        let updated = d.with(tldr: "neu")
        XCTAssertEqual(updated.tldr, "neu")
        // alles andere unverändert
        XCTAssertEqual(updated.title, d.title)
        XCTAssertEqual(updated.wordCount, d.wordCount)
        XCTAssertEqual(updated.participants, d.participants)
        XCTAssertEqual(updated.audioURL, d.audioURL)
        XCTAssertEqual(updated.lifecycle, d.lifecycle)
    }

    func testIdentityAndTimeFieldsAreNeverChanged() {
        let d = sample()
        let updated = d.with(title: "X", lifecycle: .done)
        XCTAssertEqual(updated.id, "m1")
        XCTAssertEqual(updated.dateLong, "Montag, 09. Juni")
        XCTAssertEqual(updated.timeRange, "14:00 – 14:30")
        XCTAssertEqual(updated.duration, "30m")
        XCTAssertEqual(updated.platform, .call)
    }

    func testNilAudioURLKeepsExistingValue() {
        // Dokumentierte Semantik: nil = unverändert lassen (wie der frühere rebuiltDetail).
        let d = sample()
        XCTAssertEqual(d.with(audioURL: nil).audioURL, "/tmp/a.wav")
    }

    func testLifecycleAndTasksCanBeReplaced() {
        let d = sample()
        let tasks = [ActionItem(id: "m1-task-0", who: "S1", task: "tun", due: "", status: .open)]
        let updated = d.with(tasks: tasks, lifecycle: .done)
        XCTAssertEqual(updated.tasks, tasks)
        XCTAssertEqual(updated.lifecycle, .done)
    }
}
