import XCTest
@testable import NeoQuill

final class SpeakerStoreCrossMeetingTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: SpeakerStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoQuillTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = SpeakerStore(url: tempDirectory.appendingPathComponent("speakers.sqlite"))
    }

    override func tearDown() {
        store = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testRecordsAndFindsExactMatchAcrossMeetings() {
        let embedding: [Float] = [0.6, 0.4, 0.2, 0.5]
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: embedding)
        store.recordMeetingEmbedding(meetingId: "rec-002", internalId: "S2", embedding: embedding)

        let matches = store.meetingMatches(for: embedding, threshold: 0.95)
        let meetingIds = Set(matches.map(\.meetingId))

        XCTAssertEqual(meetingIds, ["rec-001", "rec-002"])
        XCTAssertTrue(matches.allSatisfy { $0.score > 0.99 })
    }

    func testIgnoresEmbeddingsBelowThreshold() {
        let stored: [Float] = [1, 0, 0, 0]
        let other:  [Float] = [0, 1, 0, 0]
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: stored)

        let matches = store.meetingMatches(for: other, threshold: 0.5)

        XCTAssertTrue(matches.isEmpty, "Orthogonale Embeddings duerfen keinen Match liefern")
    }

    func testExcludingMeetingFiltersThatMeetingFromResults() {
        let embedding: [Float] = [0.3, 0.7, 0.1, 0.5]
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: embedding)
        store.recordMeetingEmbedding(meetingId: "rec-002", internalId: "S1", embedding: embedding)
        store.recordMeetingEmbedding(meetingId: "rec-003", internalId: "S2", embedding: embedding)

        let matches = store.meetingMatches(for: embedding, excluding: "rec-001")
        let meetingIds = Set(matches.map(\.meetingId))

        XCTAssertEqual(meetingIds, ["rec-002", "rec-003"])
    }

    func testUpsertReplacesEmbeddingForSameMeetingAndInternalId() {
        let initial:  [Float] = [1, 0, 0, 0]
        let upgraded: [Float] = [0, 1, 0, 0]
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: initial)
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: upgraded)

        let viaInitial = store.meetingMatches(for: initial, threshold: 0.95)
        let viaUpgraded = store.meetingMatches(for: upgraded, threshold: 0.95)

        XCTAssertTrue(viaInitial.isEmpty, "Altes Embedding muss ueberschrieben sein")
        XCTAssertEqual(viaUpgraded.first?.meetingId, "rec-001")
    }

    func testReadsStoredMeetingEmbeddingForLaterSpeakerLabeling() {
        let embedding: [Float] = [0.2, 0.4, 0.6, 0.8]
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: embedding)

        XCTAssertEqual(store.meetingEmbedding(meetingId: "rec-001", internalId: "S1"), embedding)
        XCTAssertNil(store.meetingEmbedding(meetingId: "rec-001", internalId: "missing"))
    }

    func testRenameMeetingInternalIdUpdatesRow() {
        let embedding: [Float] = [0.2, 0.6, 0.4, 0.5]
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: embedding)

        store.renameMeetingInternalId(meetingId: "rec-001", from: "S1", to: "TF")

        let matches = store.meetingMatches(for: embedding, threshold: 0.95)
        XCTAssertEqual(matches.first?.internalId, "TF")
    }

    func testIgnoresEmptyEmbeddingOnRecord() {
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: [])

        let probe: [Float] = [0.1, 0.2, 0.3, 0.4]
        XCTAssertTrue(store.meetingMatches(for: probe).isEmpty)
    }

    func testIgnoresEmptyEmbeddingOnQuery() {
        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: [0.5, 0.5, 0.5])

        XCTAssertTrue(store.meetingMatches(for: []).isEmpty)
    }

    func testResultsAreSortedByScoreDescending() {
        let canonical: [Float] = [1, 0, 0]
        let veryClose: [Float] = [0.99, 0.05, 0.02]
        let kindaClose: [Float] = [0.85, 0.3, 0.0]

        store.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: kindaClose)
        store.recordMeetingEmbedding(meetingId: "rec-002", internalId: "S1", embedding: veryClose)

        let matches = store.meetingMatches(for: canonical, threshold: 0.5)

        XCTAssertEqual(matches.first?.meetingId, "rec-002")
        XCTAssertEqual(matches.last?.meetingId, "rec-001")
        XCTAssertGreaterThan(matches.first?.score ?? 0, matches.last?.score ?? 1)
    }
}
