import XCTest
@testable import NeoQuill

final class TrialBannerViewTests: XCTestCase {

    private func snapshot(_ status: LicenseStatus) -> LicenseSnapshot {
        LicenseSnapshot(
            status: status, mode: .enforced,
            firstLaunchDate: nil, cutoffDate: nil, activation: nil
        )
    }

    func test_trial_showsCountdown() {
        let content = TrialBannerView.bannerContent(for: snapshot(.trial(daysRemaining: 7)))
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.headline, "Trial läuft")
        XCTAssertTrue(content?.sub.contains("7 Tage") ?? false)
    }

    func test_trial_oneDay_usesSingularLabel() {
        let content = TrialBannerView.bannerContent(for: snapshot(.trial(daysRemaining: 1)))
        XCTAssertTrue(content?.sub.contains("1 Tag ") ?? false, "1-Tag-Form muss Singular sein")
    }

    func test_trialExpired_showsExpiredBanner() {
        let content = TrialBannerView.bannerContent(for: snapshot(.trialExpired))
        XCTAssertEqual(content?.headline, "Trial abgelaufen")
    }

    func test_invalidated_showsReactivationBanner() {
        let content = TrialBannerView.bannerContent(for: snapshot(.invalidated(reason: .refunded)))
        XCTAssertEqual(content?.headline, "Lizenz ungültig")
        XCTAssertEqual(content?.cta, "Aktivieren")
    }

    func test_notRequired_showsNoBanner() {
        XCTAssertNil(TrialBannerView.bannerContent(for: snapshot(.notRequired)))
    }

    func test_betaGrace_showsNoBanner() {
        XCTAssertNil(TrialBannerView.bannerContent(for: snapshot(.betaGrace)))
    }

    func test_activated_showsNoBanner() {
        let content = TrialBannerView.bannerContent(for: snapshot(
            .activated(tier: .lifetime, lastValidatedAt: Date())
        ))
        XCTAssertNil(content)
    }
}
