import XCTest
@testable import PersonalBrowser

final class SiteLinkOpeningPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var preferences: SiteLinkOpeningPreferences!

    override func setUp() {
        super.setUp()
        let suite = "SiteLinkOpeningPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        preferences = SiteLinkOpeningPreferences(defaults: defaults)
    }

    func testSiteKeyUsesRegistrableSiteAcrossOrdinarySubdomains() {
        XCTAssertEqual(
            SiteLinkOpeningPreferences.siteKey(
                for: URL(string: "https://www.linkedin.com/feed")
            ),
            "linkedin.com"
        )
        XCTAssertEqual(
            SiteLinkOpeningPreferences.siteKey(
                for: URL(string: "https://news.example.co.uk/story")
            ),
            "example.co.uk"
        )
        XCTAssertEqual(
            SiteLinkOpeningPreferences.siteKey(
                for: URL(string: "https://accounts.google.com/signin")
            ),
            "google.com"
        )
    }

    func testFacebookSubdomainsShareOneSitePreference() {
        preferences.setPolicy(.subtab, for: URL(string: "https://www.facebook.com/feed"))

        XCTAssertEqual(
            preferences.policy(for: URL(string: "https://m.facebook.com/reel/123")),
            .subtab
        )
        XCTAssertFalse(
            SiteLinkOpeningPreferences.isExternalLink(
                from: URL(string: "https://facebook.com/feed"),
                to: URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com")
            )
        )
    }

    func testGeminiNotebookAndGoogleAuthenticationStayWithinTheGoogleSite() {
        XCTAssertEqual(
            SiteLinkOpeningPreferences.siteKey(
                for: URL(string: "https://notebooklm.google.com/")
            ),
            "google.com"
        )
        XCTAssertEqual(
            SiteLinkOpeningPreferences.siteKey(
                for: URL(string: "https://notebook.google.com/trynow")
            ),
            "google.com"
        )
        XCTAssertFalse(
            SiteLinkOpeningPreferences.isExternalLink(
                from: URL(string: "https://notebook.google.com/"),
                to: URL(string: "https://accounts.google.com/signin")
            )
        )
    }

    func testPolicyPersistsForTheSourceSiteButNotAnUnrelatedSite() {
        preferences.setPolicy(
            .subtab,
            for: URL(string: "https://www.example.com/article")
        )

        let restored = SiteLinkOpeningPreferences(defaults: defaults)
        XCTAssertEqual(
            restored.policy(for: URL(string: "https://example.com/profile")),
            .subtab
        )
        XCTAssertEqual(
            restored.policy(for: URL(string: "https://account.example.com/profile")),
            .subtab
        )
        XCTAssertEqual(
            restored.policy(for: URL(string: "https://different.example.net/profile")),
            .followWebsite
        )

        restored.setPolicy(
            .followWebsite,
            for: URL(string: "https://example.com/latest")
        )
        XCTAssertFalse(restored.hasStoredPolicy(for: URL(string: "https://example.com")))
    }

    func testExternalLinkComparisonUsesTheRegistrableSite() {
        XCTAssertFalse(
            SiteLinkOpeningPreferences.isExternalLink(
                from: URL(string: "https://www.linkedin.com/feed"),
                to: URL(string: "https://linkedin.com/in/example")
            )
        )
        XCTAssertFalse(
            SiteLinkOpeningPreferences.isExternalLink(
                from: URL(string: "https://mail.google.com/mail"),
                to: URL(string: "https://accounts.google.com/signin")
            )
        )
        XCTAssertTrue(
            SiteLinkOpeningPreferences.isExternalLink(
                from: URL(string: "https://mail.google.com/mail"),
                to: URL(string: "https://accounts.example.com/signin")
            )
        )
    }

    func testUnrelatedMultiTenantHostsNeverShareAPreference() {
        preferences.setPolicy(
            .newTab,
            for: URL(string: "https://alice.github.io/project")
        )

        XCTAssertEqual(
            preferences.policy(for: URL(string: "https://alice.github.io/other")),
            .newTab
        )
        XCTAssertEqual(
            preferences.policy(for: URL(string: "https://bob.github.io/project")),
            .followWebsite
        )
        XCTAssertTrue(
            SiteLinkOpeningPreferences.isExternalLink(
                from: URL(string: "https://one.pages.dev"),
                to: URL(string: "https://two.pages.dev")
            )
        )
    }

    func testLegacyPreviewPanelValueDecodesAsSubtab() throws {
        let decoded = try JSONDecoder().decode(
            BrowserLinkOpeningPolicy.self,
            from: Data("\"previewPanel\"".utf8)
        )

        XCTAssertEqual(decoded, .subtab)
    }

    func testLegacyExactHostPoliciesMigrateToTheNormalizedSiteKey() {
        defaults.set(
            ["m.facebook.com": BrowserLinkOpeningPolicy.newTab.rawValue],
            forKey: "siteExternalLinkOpeningPolicies"
        )

        let migrated = SiteLinkOpeningPreferences(defaults: defaults)

        XCTAssertEqual(
            migrated.policy(for: URL(string: "https://www.facebook.com/feed")),
            .newTab
        )
        XCTAssertEqual(
            defaults.dictionary(forKey: "siteExternalLinkOpeningPolicies") as? [String: String],
            ["facebook.com": BrowserLinkOpeningPolicy.newTab.rawValue]
        )
    }
}
