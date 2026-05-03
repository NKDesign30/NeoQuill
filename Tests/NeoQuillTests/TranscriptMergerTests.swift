import XCTest
@testable import NeoQuill

final class TranscriptMergerTests: XCTestCase {
    func testCaptionSpeakerWinsOverDiarization() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:04",
            startSeconds: 4,
            endSeconds: 7,
            body: "Wir sollten das bis Freitag ausrollen.",
            source: .system,
            speakerSource: .unknown
        )
        let caption = CaptionEvent(
            platform: .teams,
            appBundleIdentifier: "com.microsoft.teams2",
            speakerName: "Sarah Ebner",
            text: "Wir sollten das bis Freitag ausrollen.",
            startSeconds: 4.2,
            endSeconds: 7.2,
            confidence: 0.91
        )
        let diarized = DiarizedSpeakerSegment(
            start: 3.8,
            end: 7.4,
            speakerId: "S2",
            embedding: [0.1, 0.2, 0.3]
        )

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [caption],
            diarization: [diarized]
        )

        XCTAssertEqual(merged.first?.displayName, "Sarah Ebner")
        XCTAssertEqual(merged.first?.who, "SE")
        XCTAssertEqual(merged.first?.speakerSource, .caption)
    }

    func testPlatformApiWinsOverCaption() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:04",
            startSeconds: 4,
            endSeconds: 7,
            body: "Wir sollten das bis Freitag ausrollen.",
            source: .system,
            speakerSource: .unknown
        )
        let caption = CaptionEvent(
            platform: .teams,
            appBundleIdentifier: "com.microsoft.teams2",
            speakerName: "Live Caption Name",
            text: "Wir sollten das bis Freitag ausrollen.",
            startSeconds: 4,
            endSeconds: 7,
            confidence: 0.88
        )
        let platformEvent = PlatformTranscriptEvent(
            platform: .teams,
            speakerName: "Graph Transcript Name",
            speakerId: "aad-user-1",
            text: "Wir sollten das bis Freitag ausrollen.",
            startSeconds: 4,
            endSeconds: 7,
            confidence: 0.98
        )

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [caption],
            platformTranscriptEvents: [platformEvent],
            diarization: []
        )

        XCTAssertEqual(merged.first?.displayName, "Graph Transcript Name")
        XCTAssertEqual(merged.first?.speakerSource, .platformApi)
    }

    func testLocalSpeakerIsPreservedAndNormalizedToMe() {
        let legacyLine = TranscriptLine(
            who: "NK",
            displayName: "Legacy User",
            timestamp: "00:01",
            startSeconds: 1,
            endSeconds: 2,
            body: "Hallo zusammen.",
            source: .mic,
            speakerSource: .unknown
        )
        let caption = CaptionEvent(
            platform: .teams,
            appBundleIdentifier: "com.microsoft.teams2",
            speakerName: "Remote Person",
            text: "Hallo zusammen.",
            startSeconds: 1,
            endSeconds: 2,
            confidence: 0.95
        )

        let merged = TranscriptMerger.merge(
            audioLines: [legacyLine],
            captionEvents: [caption],
            diarization: []
        )

        XCTAssertEqual(merged.first?.who, LocalSpeakerProfile.id)
        XCTAssertEqual(merged.first?.speakerSource, .microphoneOwner)
        XCTAssertEqual(merged.first?.displayName, "Legacy User")
    }

    func testDiarizationFillsSpeakerWhenNoCaptionMatches() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:10",
            startSeconds: 10,
            endSeconds: 12,
            body: "Das klingt gut.",
            source: .system,
            speakerSource: .unknown
        )
        let diarized = DiarizedSpeakerSegment(
            start: 9.8,
            end: 12.2,
            speakerId: "S3",
            embedding: [0.4, 0.5, 0.6],
            confidence: 0.72
        )

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [],
            diarization: [diarized]
        )

        XCTAssertEqual(merged.first?.who, "S3")
        XCTAssertEqual(merged.first?.speakerSource, .diarization)
        XCTAssertEqual(merged.first?.confidence, 0.72)
    }
}
