import XCTest
@testable import NeoQuill

final class CalendarParticipantsServiceTests: XCTestCase {

    private typealias Candidate = CalendarParticipantsService.EventCandidate<String>

    func testBestActiveEventPicksSurroundingMeetingWithAttendees() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let candidates: [Candidate] = [
            Candidate(start: now.addingTimeInterval(-300), end: now.addingTimeInterval(300),
                      hasAttendees: false, payload: "no-attendees"),
            Candidate(start: now.addingTimeInterval(-200), end: now.addingTimeInterval(400),
                      hasAttendees: true,  payload: "with-attendees"),
            Candidate(start: now.addingTimeInterval(120),  end: now.addingTimeInterval(900),
                      hasAttendees: true,  payload: "upcoming"),
        ]

        let pick = CalendarParticipantsService.bestCandidate(in: candidates, at: now)
        XCTAssertEqual(pick?.payload, "with-attendees")
    }

    func testFallsBackToSurroundingWithoutAttendees() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let candidates: [Candidate] = [
            Candidate(start: now.addingTimeInterval(-100), end: now.addingTimeInterval(200),
                      hasAttendees: false, payload: "surrounding-empty"),
        ]

        let pick = CalendarParticipantsService.bestCandidate(in: candidates, at: now)
        XCTAssertEqual(pick?.payload, "surrounding-empty")
    }

    func testFallsBackToImminentMeeting() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let candidates: [Candidate] = [
            Candidate(start: now.addingTimeInterval(60),   end: now.addingTimeInterval(900),
                      hasAttendees: false, payload: "imminent"),
            Candidate(start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200),
                      hasAttendees: true,  payload: "far-future"),
        ]

        let pick = CalendarParticipantsService.bestCandidate(in: candidates, at: now)
        XCTAssertEqual(pick?.payload, "imminent")
    }

    func testReturnsNilWhenNothingCloseEnough() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let candidates: [Candidate] = [
            Candidate(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-1800),
                      hasAttendees: true,  payload: "past"),
            Candidate(start: now.addingTimeInterval(7200),  end: now.addingTimeInterval(10800),
                      hasAttendees: true,  payload: "far-future"),
        ]

        let pick = CalendarParticipantsService.bestCandidate(in: candidates, at: now)
        XCTAssertNil(pick)
    }

    func testImminentMeetingIsCappedAt5Minutes() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let inSixMin: [Candidate] = [
            Candidate(start: now.addingTimeInterval(360), end: now.addingTimeInterval(900),
                      hasAttendees: true, payload: "six-minutes"),
        ]

        XCTAssertNil(CalendarParticipantsService.bestCandidate(in: inSixMin, at: now))
    }
}
