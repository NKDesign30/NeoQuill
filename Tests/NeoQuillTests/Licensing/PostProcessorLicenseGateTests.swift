import XCTest
@testable import NeoQuill

/// Slice E2 — License-Gate im PostProcessor.
///
/// Wenn das Gate `false` liefert, soll keine AI-Summary geholt werden und
/// das Ergebnis die Fallback-Werte (Title/TLDR aus erstem Satz, keine
/// Highlights/Tasks/Chapters) zeigen.
final class PostProcessorLicenseGateTests: XCTestCase {

    func test_blocked_returnsFallback_andSkipsSummary() async {
        // Setup: Default-Defaults so dass ohne Gate ein Summary-Versuch laufen würde.
        let defaults = UserDefaults.standard
        let prevClaude = defaults.object(forKey: AppSettings.claudeAnalysisEnabled)
        let prevLocalOnly = defaults.object(forKey: AppSettings.localOnlyMode)
        defaults.set(true, forKey: AppSettings.claudeAnalysisEnabled)
        defaults.set(false, forKey: AppSettings.localOnlyMode)
        defer {
            if let prevClaude { defaults.set(prevClaude, forKey: AppSettings.claudeAnalysisEnabled) }
            else { defaults.removeObject(forKey: AppSettings.claudeAnalysisEnabled) }
            if let prevLocalOnly { defaults.set(prevLocalOnly, forKey: AppSettings.localOnlyMode) }
            else { defaults.removeObject(forKey: AppSettings.localOnlyMode) }
        }

        let body = "Lizenz abgelaufen, keine Summary erlaubt."
        let line = TranscriptLine(who: "ME", timestamp: "00:00", body: body)

        var gateInvocations = 0
        let result = await PostProcessor.process(
            meetingId: "test-gate-\(UUID().uuidString)",
            transcriptLines: [line],
            locale: "de",
            licenseAllowsSummary: {
                gateInvocations += 1
                return false
            }
        )

        XCTAssertEqual(gateInvocations, 1, "Gate muss genau einmal befragt werden")
        XCTAssertEqual(result.title, body, "Bei Block: Fallback-Title aus erstem Satz")
        XCTAssertEqual(result.tldr, body, "Bei Block: Fallback-TLDR aus erstem Satz")
        XCTAssertTrue(result.highlights.isEmpty)
        XCTAssertTrue(result.tasks.isEmpty)
        XCTAssertTrue(result.chapters.isEmpty)
    }

    func test_emptyTranscript_doesNotInvokeGate() async {
        var gateInvocations = 0
        let result = await PostProcessor.process(
            meetingId: "test-empty-\(UUID().uuidString)",
            transcriptLines: [],
            locale: "de",
            licenseAllowsSummary: {
                gateInvocations += 1
                return true
            }
        )

        XCTAssertEqual(gateInvocations, 0, "Bei leerem Transkript darf das Gate nicht angefragt werden")
        XCTAssertEqual(result.title, "Aufnahme ohne Sprache")
    }
}
