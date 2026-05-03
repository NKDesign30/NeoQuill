import XCTest
@testable import NeoQuill

final class TranscriptLineMigrationTests: XCTestCase {
    func testLegacyTranscriptLineDecodesWithDefaults() throws {
        let json = """
        {
          "who": "NK",
          "timestamp": "01:23",
          "body": "Legacy transcript.",
          "highlight": true
        }
        """.data(using: .utf8)!

        let line = try JSONDecoder().decode(TranscriptLine.self, from: json)

        XCTAssertEqual(line.who, "NK")
        XCTAssertEqual(line.startSeconds, 83)
        XCTAssertEqual(line.endSeconds, 83)
        XCTAssertEqual(line.body, "Legacy transcript.")
        XCTAssertEqual(line.source, .merged)
        XCTAssertEqual(line.speakerSource, .microphoneOwner)
        XCTAssertTrue(line.highlight)
    }
}
