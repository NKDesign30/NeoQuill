import XCTest
@testable import NeoQuill

final class BetaGraceResolverTests: XCTestCase {

    private let cutoff = Date(timeIntervalSince1970: 1_790_000_000)
    private let oneDay: TimeInterval = 86_400

    func test_grantsGrace_whenMarkerIsBeforeCutoff() {
        let early = cutoff.addingTimeInterval(-30 * oneDay)
        let decision = BetaGraceResolver.resolve(firstLaunchDate: early, cutoffDate: cutoff)
        XCTAssertEqual(decision, .grace)
    }

    func test_doesNotGrant_whenMarkerExactlyAtCutoff() {
        let decision = BetaGraceResolver.resolve(firstLaunchDate: cutoff, cutoffDate: cutoff)
        XCTAssertEqual(decision, .notEligible(reason: .launchedAfterCutoff))
    }

    func test_doesNotGrant_whenMarkerAfterCutoff() {
        let late = cutoff.addingTimeInterval(oneDay)
        let decision = BetaGraceResolver.resolve(firstLaunchDate: late, cutoffDate: cutoff)
        XCTAssertEqual(decision, .notEligible(reason: .launchedAfterCutoff))
    }

    func test_doesNotGrant_whenMarkerIsMissing() {
        let decision = BetaGraceResolver.resolve(firstLaunchDate: nil, cutoffDate: cutoff)
        XCTAssertEqual(decision, .notEligible(reason: .noFirstLaunchMarker))
    }

    func test_doesNotGrant_whenCutoffIsMissing() {
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let decision = BetaGraceResolver.resolve(firstLaunchDate: early, cutoffDate: nil)
        XCTAssertEqual(decision, .notEligible(reason: .noCutoffDate))
    }

    func test_doesNotGrant_whenBothMissing() {
        let decision = BetaGraceResolver.resolve(firstLaunchDate: nil, cutoffDate: nil)
        // FirstLaunchDate-Check kommt zuerst
        XCTAssertEqual(decision, .notEligible(reason: .noFirstLaunchMarker))
    }
}
