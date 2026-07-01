import XCTest
@testable import NeoQuill

final class RecordingControllerSpeakerIdentityTests: XCTestCase {
    @MainActor
    func testKnownSpeakerIdWinsOverGeneratedSlug() {
        let id = SpeakerIdentityCoordinator.canonicalId(
            name: "Morgan Lee",
            knownSpeakerId: "speaker-morgan-2026"
        )

        XCTAssertEqual(id, "speaker-morgan-2026")
    }

    @MainActor
    func testExistingSpeakerNameReusesLegacyIdentity() {
        let existing = labeledSpeaker(id: "TF", name: "Morgan Lee")
        let id = SpeakerIdentityCoordinator.canonicalId(
            name: " morgan   lee ",
            knownSpeakerId: "   ",
            existingSpeakers: [existing]
        )

        XCTAssertEqual(id, "TF")
    }

    @MainActor
    func testNewMultiWordSpeakerUsesStableNameSlug() {
        let id = SpeakerIdentityCoordinator.canonicalId(
            name: "Morgan Lee",
            knownSpeakerId: "   "
        )

        XCTAssertEqual(id, "speaker-morgan-lee")
    }

    @MainActor
    func testSingleNamesDoNotCollideByInitial() {
        let alexId = SpeakerIdentityCoordinator.canonicalId(name: "Alex")
        let caseyId = SpeakerIdentityCoordinator.canonicalId(name: "Casey")

        XCTAssertEqual(alexId, "speaker-alex")
        XCTAssertEqual(caseyId, "speaker-casey")
        XCTAssertNotEqual(alexId, caseyId)
    }

    @MainActor
    func testGeneratedSpeakerIdNormalizesDiacritics() {
        let id = SpeakerIdentityCoordinator.canonicalId(name: "Jörg Müller")

        XCTAssertEqual(id, "speaker-jorg-muller")
    }

    @MainActor
    func testLabelSpeakerDoesNotBackfillCrossMeetingsWhenLicenseBlocks() {
        let harness = makeBackfillHarness()
        defer { harness.cleanup() }
        harness.recorder.licenseAllowsCrossMeetingSpeakerID = { false }

        let migrated = harness.recorder.labelSpeaker(
            internalId: "S1",
            name: "Alex",
            colorHex: 0x2EAB73,
            meetingId: "meeting-current"
        )

        XCTAssertEqual(migrated, 0)
        XCTAssertEqual(harness.meetingStore.detail(for: "meeting-current")?.participants.first?.id, "speaker-alex")
        XCTAssertEqual(harness.meetingStore.detail(for: "meeting-other")?.participants.first?.id, "S2")
        XCTAssertNotNil(harness.speakerStore.meetingEmbedding(meetingId: "meeting-other", internalId: "S2"))
    }

    @MainActor
    func testLabelSpeakerBackfillsCrossMeetingsWhenLicenseAllows() {
        let harness = makeBackfillHarness()
        defer { harness.cleanup() }
        harness.recorder.licenseAllowsCrossMeetingSpeakerID = { true }

        let migrated = harness.recorder.labelSpeaker(
            internalId: "S1",
            name: "Alex",
            colorHex: 0x2EAB73,
            meetingId: "meeting-current"
        )

        XCTAssertEqual(migrated, 1)
        XCTAssertEqual(harness.meetingStore.detail(for: "meeting-other")?.participants.first?.id, "speaker-alex")
        XCTAssertNil(harness.speakerStore.meetingEmbedding(meetingId: "meeting-other", internalId: "S2"))
        XCTAssertNotNil(harness.speakerStore.meetingEmbedding(meetingId: "meeting-other", internalId: "speaker-alex"))
    }

    private func labeledSpeaker(id: String, name: String) -> LabeledSpeaker {
        LabeledSpeaker(
            id: id,
            name: name,
            embedding: [],
            colorHex: 0x2EAB73,
            createdAt: Date(timeIntervalSince1970: 0),
            lastSeenAt: Date(timeIntervalSince1970: 0)
        )
    }

    @MainActor
    private func makeBackfillHarness() -> BackfillHarness {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingControllerSpeakerIdentityTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        UserDefaults.standard.set(false, forKey: AppSettings.autoDetectMeetings.key)

        let meetingStore = MeetingStore(url: tempDirectory.appendingPathComponent("meetings.sqlite"))
        let speakerStore = SpeakerStore(url: tempDirectory.appendingPathComponent("speakers.sqlite"))
        let recorder = RecordingController()
        recorder.store = meetingStore
        recorder.speakerStore = speakerStore

        let embedding: [Float] = [0.8, 0.2, 0.4, 0.1]
        speakerStore.recordMeetingEmbedding(meetingId: "meeting-current", internalId: "S1", embedding: embedding)
        speakerStore.recordMeetingEmbedding(meetingId: "meeting-other", internalId: "S2", embedding: embedding)
        meetingStore.insert(
            summary: summary(id: "meeting-current", participantId: "S1"),
            detail: detail(id: "meeting-current", speakerId: "S1")
        )
        meetingStore.insert(
            summary: summary(id: "meeting-other", participantId: "S2"),
            detail: detail(id: "meeting-other", speakerId: "S2")
        )
        return BackfillHarness(
            tempDirectory: tempDirectory,
            recorder: recorder,
            meetingStore: meetingStore,
            speakerStore: speakerStore
        )
    }

    private func summary(id: String, participantId: String) -> MeetingSummary {
        MeetingSummary(
            id: id,
            title: "Meeting",
            date: "25. Mai",
            time: "12:00",
            duration: "10m",
            platform: .zoom,
            wordCount: 10,
            group: "Heute",
            participantIds: [participantId],
            unread: true
        )
    }

    private func detail(id: String, speakerId: String) -> MeetingDetail {
        MeetingDetail(
            id: id,
            title: "Meeting",
            dateLong: "Montag, 25. Mai",
            timeRange: "12:00 - 12:10",
            duration: "10m",
            platform: .zoom,
            wordCount: 10,
            participants: [
                Participant(id: speakerId, name: "Speaker \(speakerId)", role: "Erkannt", colorHex: 0x7C8AFF, spoke: "2m")
            ],
            tldr: "Speaker \(speakerId) sagt Hallo.",
            highlights: [],
            tasks: [],
            chapters: [],
            transcript: [
                TranscriptLine(who: speakerId, displayName: "Speaker \(speakerId)", timestamp: "00:01", body: "Hallo.")
            ]
        )
    }

    private struct BackfillHarness {
        let tempDirectory: URL
        let recorder: RecordingController
        let meetingStore: MeetingStore
        let speakerStore: SpeakerStore

        func cleanup() {
            try? FileManager.default.removeItem(at: tempDirectory)
            UserDefaults.standard.removeObject(forKey: AppSettings.autoDetectMeetings.key)
        }
    }
}
