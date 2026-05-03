import XCTest
@testable import NeoQuill

final class PlatformTranscriptMergeTests: XCTestCase {
    func testPlatformEventBeatsCaptionWhenBothMatch() {
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
            speakerName: "Caption Sarah",
            text: "Wir sollten das bis Freitag ausrollen.",
            startSeconds: 4.2,
            endSeconds: 7.1,
            confidence: 0.85
        )
        let platform = PlatformTranscriptEvent(
            platform: .teams,
            speakerName: "Sarah Ebner",
            speakerId: "user-001",
            text: "Wir sollten das bis Freitag ausrollen.",
            startSeconds: 4.0,
            endSeconds: 7.0,
            confidence: 0.96
        )

        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [caption],
            platformTranscriptEvents: [platform],
            diarization: []
        )
        XCTAssertEqual(merged.first?.displayName, "Sarah Ebner")
        XCTAssertEqual(merged.first?.speakerSource, .platformApi)
    }

    func testHiddenIdentityFromPlatformDropsToCaption() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:02",
            startSeconds: 2,
            endSeconds: 5,
            body: "Wir teilen das Whiteboard.",
            source: .system,
            speakerSource: .unknown
        )
        let platformHidden = PlatformTranscriptEvent(
            platform: .teams,
            speakerName: "Hidden Identity",
            speakerId: "user-x",
            text: "Wir teilen das Whiteboard.",
            startSeconds: 2,
            endSeconds: 5,
            confidence: 0.96
        )
        let caption = CaptionEvent(
            platform: .teams,
            appBundleIdentifier: "com.microsoft.teams2",
            speakerName: "Lisa Müller",
            text: "Wir teilen das Whiteboard.",
            startSeconds: 2.1,
            endSeconds: 5.0,
            confidence: 0.86
        )
        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: [caption],
            platformTranscriptEvents: [platformHidden],
            diarization: []
        )
        XCTAssertEqual(merged.first?.displayName, "Lisa Müller")
        XCTAssertEqual(merged.first?.speakerSource, .caption)
    }

    func testDuplicateCaptionsDoNotBreakMerge() {
        let line = TranscriptLine(
            who: "S1",
            timestamp: "00:08",
            startSeconds: 8,
            endSeconds: 11,
            body: "Ich übernehme die Doku.",
            source: .system,
            speakerSource: .unknown
        )
        let captions = (0..<5).map { idx in
            CaptionEvent(
                platform: .teams,
                appBundleIdentifier: "com.microsoft.teams2",
                speakerName: "Tom Friedrich",
                text: "Ich übernehme die Doku.",
                startSeconds: 8 + Double(idx) * 0.05,
                endSeconds: 11 + Double(idx) * 0.05,
                confidence: 0.88
            )
        }
        let merged = TranscriptMerger.merge(
            audioLines: [line],
            captionEvents: captions,
            diarization: []
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.displayName, "Tom Friedrich")
        XCTAssertEqual(merged.first?.speakerSource, .caption)
    }

    func testPlatformEventConvertsToCaptionEventLossless() {
        let event = PlatformTranscriptEvent(
            platform: .meet,
            speakerName: "Sarah Ebner",
            speakerId: "users/123",
            text: "Demo läuft.",
            startSeconds: 12.0,
            endSeconds: 14.5,
            confidence: 0.92,
            rawPayload: "raw"
        )
        let caption = event.captionEvent
        XCTAssertEqual(caption.platform, .meet)
        XCTAssertEqual(caption.speakerName, "Sarah Ebner")
        XCTAssertEqual(caption.speakerHandle, "users/123")
        XCTAssertEqual(caption.text, "Demo läuft.")
        XCTAssertEqual(caption.startSeconds, 12.0, accuracy: 0.001)
        XCTAssertEqual(caption.endSeconds ?? 0, 14.5, accuracy: 0.001)
        XCTAssertEqual(caption.confidence, 0.92, accuracy: 0.001)
    }
}
