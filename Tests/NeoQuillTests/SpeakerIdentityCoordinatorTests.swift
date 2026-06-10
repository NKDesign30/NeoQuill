import XCTest
@testable import NeoQuill

final class SpeakerIdentityCoordinatorTests: XCTestCase {

    typealias Kind = SpeakerIdentityCoordinator.IdentityKind

    private var tempDirectory: URL!
    private var speakerStore: SpeakerStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoQuillTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        speakerStore = SpeakerStore(url: tempDirectory.appendingPathComponent("speakers.sqlite"))
    }

    override func tearDown() {
        speakerStore = nil
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - label(...)

    /// Der historische Bug: der In-Memory-Cache der LETZTEN Aufnahme gewann
    /// gegen das meeting-bezogen persistierte Embedding. Wer nach einer neuen
    /// Aufnahme "S1" in einem älteren Meeting labelte, schrieb das Embedding
    /// des falschen Meetings ins Profil. Der Kontrakt ist jetzt umgekehrt.
    func testLabelPrefersMeetingScopedEmbeddingOverCachedEmbedding() {
        let meetingScoped: [Float] = [1, 0, 0, 0]
        let staleCache: [Float] = [0, 1, 0, 0]
        speakerStore.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: meetingScoped)

        let coordinator = SpeakerIdentityCoordinator(speakerStore: speakerStore)
        coordinator.label(
            meetingId: "rec-001",
            internalId: "S1",
            name: "Thorsten",
            colorHex: 0x2EAB73,
            cachedEmbedding: staleCache,
            allowCrossMeetingBackfill: false
        )

        let viaMeetingScoped = speakerStore.bestMatch(for: meetingScoped)
        XCTAssertEqual(viaMeetingScoped?.id, "speaker-thorsten",
                       "Profil muss das meeting-bezogene Embedding tragen")
        XCTAssertNil(speakerStore.bestMatch(for: staleCache),
                     "Der stale Cache der letzten Aufnahme darf NICHT im Profil landen")
    }

    func testLabelFallsBackToCachedEmbeddingWhenMeetingHasNone() {
        let cached: [Float] = [0, 0, 1, 0]
        let coordinator = SpeakerIdentityCoordinator(speakerStore: speakerStore)
        coordinator.label(
            meetingId: "rec-002",
            internalId: "S1",
            name: "Anna",
            colorHex: 0x7C8AFF,
            cachedEmbedding: cached,
            allowCrossMeetingBackfill: false
        )
        XCTAssertEqual(speakerStore.bestMatch(for: cached)?.id, "speaker-anna")
    }

    func testLabelWithoutBackfillPermissionReturnsZeroAndTouchesNoOtherMeeting() {
        let embedding: [Float] = [0.6, 0.4, 0.2, 0.5]
        speakerStore.recordMeetingEmbedding(meetingId: "rec-001", internalId: "S1", embedding: embedding)
        speakerStore.recordMeetingEmbedding(meetingId: "rec-002", internalId: "S2", embedding: embedding)

        let coordinator = SpeakerIdentityCoordinator(speakerStore: speakerStore)
        let migrated = coordinator.label(
            meetingId: "rec-001",
            internalId: "S1",
            name: "Thorsten",
            colorHex: 0x2EAB73,
            allowCrossMeetingBackfill: false
        )

        XCTAssertEqual(migrated, 0)
        XCTAssertNotNil(speakerStore.meetingEmbedding(meetingId: "rec-002", internalId: "S2"),
                        "Ohne Backfill-Erlaubnis bleibt das andere Meeting unangetastet")
    }

    func testCaptionKindMapsToCaptionSourceWithoutExternalId() {
        XCTAssertEqual(Kind.caption.lineSource, .caption)
        XCTAssertEqual(Kind.caption.aliasSource, "caption")
        XCTAssertNil(Kind.caption.externalId(for: "S2"))
    }

    func testPlatformKindMapsToPlatformApiWithWhoAsExternalId() {
        XCTAssertEqual(Kind.platform.lineSource, .platformApi)
        XCTAssertEqual(Kind.platform.aliasSource, "platform")
        XCTAssertEqual(Kind.platform.externalId(for: "S2"), "S2")
    }

    func testKnownSpeakerIdWins() {
        let id = SpeakerIdentityCoordinator.canonicalId(name: "Niko", knownSpeakerId: "speaker-fixed")
        XCTAssertEqual(id, "speaker-fixed")
    }

    func testGeneratesSlugFromName() {
        XCTAssertEqual(SpeakerIdentityCoordinator.canonicalId(name: "Jörg Müller"), "speaker-jorg-muller")
    }

    func testEmptyNameFallsBackToUnknownSlug() {
        XCTAssertEqual(SpeakerIdentityCoordinator.canonicalId(name: "   "), "speaker-unknown")
    }
}
