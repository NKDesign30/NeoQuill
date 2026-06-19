import XCTest
@testable import NeoQuill

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testEngineStepBlocksWhenSummaryProviderWasNotVerified() {
        let state = OnboardingState()
        state.currentStep = .engine
        state.claudeAnalysisEnabled = true
        state.summaryProviderVerified = false

        XCTAssertFalse(state.canGoNext)
        XCTAssertEqual(state.secondaryLabel, "KI später einrichten")
    }

    func testEngineStepAllowsVerifiedSummaryProvider() {
        let state = OnboardingState()
        state.currentStep = .engine
        state.claudeAnalysisEnabled = true
        state.summaryProviderVerified = true

        XCTAssertTrue(state.canGoNext)
        XCTAssertNil(state.secondaryLabel)
    }

    func testEngineSkipDisablesSummaryAndAdvances() {
        let state = OnboardingState()
        state.currentStep = .engine
        state.claudeAnalysisEnabled = true
        state.summaryProviderVerified = false

        state.skip()

        XCTAssertEqual(state.currentStep, .capture)
        XCTAssertFalse(state.claudeAnalysisEnabled)
        XCTAssertFalse(state.summaryProviderVerified)
    }

    func testReadyStepBlocksUntilRuntimeWasPrepared() {
        let state = OnboardingState()
        state.currentStep = .ready
        state.runtimePrepared = false

        XCTAssertFalse(state.canGoNext)
        XCTAssertEqual(state.primaryLabel, "Runtime vorbereiten ...")

        state.runtimePrepared = true

        XCTAssertTrue(state.canGoNext)
        XCTAssertEqual(state.primaryLabel, "NeoQuill öffnen")
    }

    func testRuntimePreparationStatusAllowsFinishWhenSpeechIsReady() {
        let ready = RuntimePreparationStatus(
            speech: .ready("Final-STT bereit."),
            diarization: .failed("Optionales Speaker-Modell fehlt.")
        )
        let failed = RuntimePreparationStatus(
            speech: .failed("Sprachruntime fehlt."),
            diarization: .skipped("Nicht aktiv.")
        )

        XCTAssertTrue(ready.canFinishOnboarding)
        XCTAssertFalse(failed.canFinishOnboarding)
    }
}
