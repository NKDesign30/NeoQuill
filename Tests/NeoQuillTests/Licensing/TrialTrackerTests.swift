import XCTest
@testable import NeoQuill

final class TrialTrackerTests: XCTestCase {

    private let day: TimeInterval = 86_400

    // MARK: - TrialEvaluator (pure)

    func test_evaluator_returnsNilStatus_whenNotStarted() {
        let status = TrialEvaluator.statusFor(startedAt: nil, lastSeen: nil, now: Date())
        XCTAssertNil(status)
    }

    func test_evaluator_returnsTrialWithFullDays_atStart() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let status = TrialEvaluator.statusFor(startedAt: now, lastSeen: now, now: now)
        XCTAssertEqual(status, .trial(daysRemaining: 14))
    }

    func test_evaluator_returnsTrialWithCorrectDays_inTheMiddle() {
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let halfway = started.addingTimeInterval(7 * day)
        let status = TrialEvaluator.statusFor(startedAt: started, lastSeen: started, now: halfway)
        XCTAssertEqual(status, .trial(daysRemaining: 7))
    }

    func test_evaluator_returnsExpired_atDay14() {
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let after14 = started.addingTimeInterval(14 * day)
        let status = TrialEvaluator.statusFor(startedAt: started, lastSeen: started, now: after14)
        XCTAssertEqual(status, .trialExpired)
    }

    func test_evaluator_returnsExpired_afterDay14() {
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let after20 = started.addingTimeInterval(20 * day)
        let status = TrialEvaluator.statusFor(startedAt: started, lastSeen: started, now: after20)
        XCTAssertEqual(status, .trialExpired)
    }

    // MARK: - Tamper-Resistance

    func test_evaluator_ignoresBackdatedClock_usesLastSeen() {
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let lastSeen = started.addingTimeInterval(10 * day)
        let backdatedNow = started.addingTimeInterval(1 * day)   // System-Uhr zurückgedreht

        let status = TrialEvaluator.statusFor(startedAt: started, lastSeen: lastSeen, now: backdatedNow)
        // Effektives jetzt ist `lastSeen` (Tag 10), nicht Tag 1 → noch 4 Tage übrig
        XCTAssertEqual(status, .trial(daysRemaining: 4))
    }

    func test_evaluator_takesNowOverLastSeen_whenNowIsForward() {
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let lastSeen = started.addingTimeInterval(3 * day)
        let now = started.addingTimeInterval(10 * day)

        let status = TrialEvaluator.statusFor(startedAt: started, lastSeen: lastSeen, now: now)
        XCTAssertEqual(status, .trial(daysRemaining: 4))
    }

    // MARK: - InMemoryTrialTracker

    func test_inMemory_startIsIdempotent() throws {
        let tracker = InMemoryTrialTracker()
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        let t1 = t0.addingTimeInterval(5 * day)

        try tracker.start(now: t0)
        try tracker.start(now: t1)

        XCTAssertEqual(tracker.startedAt(), t0, "Zweiter start() darf startedAt nicht ändern")
    }

    func test_inMemory_touch_movesLastSeenForward() throws {
        let tracker = InMemoryTrialTracker()
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        try tracker.start(now: t0)

        let t1 = t0.addingTimeInterval(2 * day)
        try tracker.touch(now: t1)
        XCTAssertEqual(tracker.lastSeen(), t1)
    }

    func test_inMemory_touch_doesNotMoveBackward() throws {
        let tracker = InMemoryTrialTracker()
        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        try tracker.start(now: t0)
        let t1 = t0.addingTimeInterval(5 * day)
        try tracker.touch(now: t1)

        let backdated = t0.addingTimeInterval(1 * day)
        try tracker.touch(now: backdated)

        XCTAssertEqual(tracker.lastSeen(), t1, "Rückwärtsbewegung muss ignoriert werden")
    }

    func test_inMemory_reset_clearsBothDates() throws {
        let tracker = InMemoryTrialTracker()
        try tracker.start(now: Date())
        tracker.reset()
        XCTAssertNil(tracker.startedAt())
        XCTAssertNil(tracker.lastSeen())
    }

    // MARK: - KeychainTrialTracker Smoke

    func test_keychain_roundtrip_smoke() throws {
        let tracker = KeychainTrialTracker()
        tracker.reset()
        defer { tracker.reset() }

        XCTAssertNil(tracker.startedAt())

        let t0 = Date(timeIntervalSince1970: 1_780_000_000)
        try tracker.start(now: t0)

        XCTAssertEqual(tracker.startedAt()?.timeIntervalSince1970 ?? 0,
                       t0.timeIntervalSince1970,
                       accuracy: 1.0)
        XCTAssertEqual(tracker.lastSeen()?.timeIntervalSince1970 ?? 0,
                       t0.timeIntervalSince1970,
                       accuracy: 1.0)

        let t1 = t0.addingTimeInterval(3 * day)
        try tracker.touch(now: t1)
        XCTAssertEqual(tracker.lastSeen()?.timeIntervalSince1970 ?? 0,
                       t1.timeIntervalSince1970,
                       accuracy: 1.0)
    }
}
