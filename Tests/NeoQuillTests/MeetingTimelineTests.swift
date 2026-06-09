import XCTest
@testable import NeoQuill

final class MeetingTimelineTests: XCTestCase {

    func testDurationShortFormatsSecondsOnly() {
        XCTAssertEqual(MeetingTimeline.durationShort(45), "45s")
        XCTAssertEqual(MeetingTimeline.durationShort(0), "0s")
    }

    func testDurationShortFormatsMinutesAndSeconds() {
        XCTAssertEqual(MeetingTimeline.durationShort(125), "2m 5s")
        XCTAssertEqual(MeetingTimeline.durationShort(60), "1m 0s")
    }

    func testTimeStringHasClockShape() {
        let value = MeetingTimeline.timeString(from: Date(timeIntervalSince1970: 1_718_000_000))
        XCTAssertTrue(value.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil, value)
    }

    func testTimeRangeStartsWithTimeShort() {
        let timeline = MeetingTimeline(started: Date(timeIntervalSince1970: 1_718_000_000), runtime: 600)
        XCTAssertTrue(timeline.timeRange.hasPrefix("\(timeline.timeShort) – "), timeline.timeRange)
    }

    func testZeroRuntimeMakesStartEqualEnd() {
        let timeline = MeetingTimeline(started: Date(timeIntervalSince1970: 1_718_000_000), runtime: 0)
        XCTAssertEqual(timeline.timeRange, "\(timeline.timeShort) – \(timeline.timeShort)")
    }

    func testDateFieldsAreNonEmpty() {
        let timeline = MeetingTimeline(started: Date(timeIntervalSince1970: 1_718_000_000), runtime: 600)
        XCTAssertFalse(timeline.dateShort.isEmpty)
        XCTAssertFalse(timeline.dateLong.isEmpty)
        XCTAssertEqual(timeline.durationShort, "10m 0s")
    }
}
