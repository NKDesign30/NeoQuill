import XCTest
@testable import NeoQuill

final class LicenseCheckoutURLsTests: XCTestCase {

    func test_allMappedVariants_produceCheckoutURLs() {
        for variantID in [
            VariantIDMap.lifetime,
            VariantIDMap.majorUpgrade,
            VariantIDMap.team5,
            VariantIDMap.team10,
        ] {
            let url = LicenseCheckoutURLs.buyURL(variantID: variantID)
            XCTAssertNotNil(url, "Variant \(variantID) sollte einen Slug haben")
            XCTAssertEqual(url?.scheme, "https")
            XCTAssertEqual(url?.host, "neon-studio.lemonsqueezy.com")
            XCTAssertTrue(url?.path.hasPrefix("/checkout/buy/") ?? false)
        }
    }

    func test_slugLookup_isUnique_acrossVariants() {
        let slugs = LicenseCheckoutURLs.slugByVariantID.values
        let unique = Set(slugs)
        XCTAssertEqual(slugs.count, unique.count, "Slugs müssen pro Variant eindeutig sein")
    }

    func test_unknownVariant_returnsNil() {
        XCTAssertNil(LicenseCheckoutURLs.buyURL(variantID: 999999))
    }

    func test_storeFallback_isReachableStoreRoot() {
        XCTAssertEqual(LicenseCheckoutURLs.storeFallback.absoluteString,
                       "https://neon-studio.lemonsqueezy.com")
    }

    func test_gateSheetCheckoutURL_usesMappedSlug_forKnownVariant() {
        let url = LicenseGateSheet.checkoutURL(variantID: VariantIDMap.lifetime)
        XCTAssertTrue(url.absoluteString.contains("/checkout/buy/"),
                      "Bekannte Variant sollte direkte Buy-URL liefern, nicht Store-Root")
    }

    func test_gateSheetCheckoutURL_fallsBackToStore_forUnknownVariant() {
        let url = LicenseGateSheet.checkoutURL(variantID: 999999)
        XCTAssertEqual(url, LicenseCheckoutURLs.storeFallback)
    }
}
