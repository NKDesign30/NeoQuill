import XCTest
@testable import NeoQuill

final class TranscriptionJobTests: XCTestCase {

    /// Der harte Timeout muss einen Langläufer beenden — das ist genau der
    /// Schutz, der beim 2,5h-Hänger fehlte (nacktes waitUntilExit).
    func testTimeoutTerminatesLongRunningProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        let start = Date()
        let finished = try TranscriptionJob.runWithTimeout(process, seconds: 0.4)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(finished, "Langläufer muss als Timeout (false) zurückkommen")
        XCTAssertFalse(process.isRunning, "Prozess muss hart beendet sein")
        XCTAssertLessThan(elapsed, 4, "Timeout muss vor dem natürlichen Ende greifen")
    }

    /// Ein schneller Prozess darf nicht fälschlich als Timeout gewertet werden.
    func testFastProcessFinishesNaturally() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let finished = try TranscriptionJob.runWithTimeout(process, seconds: 5)

        XCTAssertTrue(finished, "Schneller Prozess endet selbst (true)")
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
