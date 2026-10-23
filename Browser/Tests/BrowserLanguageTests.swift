import XCTest
@testable import PersonalBrowser

final class BrowserLanguageTests: XCTestCase {
    func testNormalizesAndDeduplicatesPreferredLanguages() {
        XCTAssertEqual(
            BrowserLanguage.normalizedIdentifiers(["fi_FI", "en-US", "FI-fi", " "]),
            ["fi-FI", "en-US"]
        )
    }

    func testUsesPrimaryIOSLanguageForSearchLanguage() {
        XCTAssertEqual(
            BrowserLanguage.primaryLanguageCode(for: ["SV_FI", "fi-FI"]),
            "sv"
        )
    }

    func testBuildsAcceptLanguageHeaderInIOSPreferenceOrder() {
        XCTAssertEqual(
            BrowserLanguage.acceptLanguageHeader(for: ["fi-FI", "en-US", "sv"]),
            "fi-FI, en-US;q=0.9, sv;q=0.8"
        )
    }

    func testRequestCarriesIOSPreferredLanguages() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let request = BrowserLanguage.request(
            for: url,
            preferredLanguages: ["fi-FI", "en-US"]
        )

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Accept-Language"),
            "fi-FI, en-US;q=0.9"
        )
    }
}
