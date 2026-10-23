import XCTest
@testable import PersonalBrowser

final class AppPromptPreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var preferences: AppPromptPreferences!

    override func setUp() {
        super.setUp()
        let suite = "AppPromptPreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        preferences = AppPromptPreferences(defaults: defaults)
    }

    func testNormalizesCommonMobileHostPrefixes() {
        XCTAssertEqual(
            AppPromptPreferences.normalizedHost(from: URL(string: "https://www.linkedin.com/feed")),
            "linkedin.com"
        )
        XCTAssertEqual(
            AppPromptPreferences.normalizedHost(from: URL(string: "https://m.linkedin.com/feed")),
            "linkedin.com"
        )
    }

    func testBlockingPersistsForNormalizedDomain() {
        preferences.setBlocked(true, url: URL(string: "https://m.linkedin.com/feed"))

        XCTAssertTrue(preferences.isBlocked(url: URL(string: "https://www.linkedin.com/posts/1")))

        preferences.setBlocked(false, url: URL(string: "https://linkedin.com/feed"))
        XCTAssertFalse(preferences.isBlocked(url: URL(string: "https://m.linkedin.com/feed")))
    }

    func testAppLinkResolverSeparatesNativeDestinationsFromOrdinaryWebLinks() {
        XCTAssertNotNil(
            ExternalAppLinkResolver.request(
                for: URL(string: "linkedin://feed"),
                sourceURL: nil
            )
        )
        XCTAssertNotNil(
            ExternalAppLinkResolver.request(
                for: URL(string: "https://apps.apple.com/app/id123"),
                sourceURL: nil
            )
        )
        XCTAssertNil(
            ExternalAppLinkResolver.request(
                for: URL(string: "https://linkedin.com/feed"),
                sourceURL: nil
            )
        )
        XCTAssertEqual(
            ExternalAppLinkResolver.request(
                for: URL(string: "mailto:hello@example.com"),
                sourceURL: nil
            )?.serviceKey,
            "email"
        )
    }

    func testBrowserNavigationRoutesActualAppDestinationsThroughUserChoice() {
        XCTAssertEqual(
            BrowserNavigationDestinationPolicy.decision(
                for: URL(string: "linkedin://signin"),
                navigationType: .linkActivated
            ),
            .handleExternalApp
        )
        XCTAssertEqual(
            BrowserNavigationDestinationPolicy.decision(
                for: URL(string: "mailto:hello@example.com"),
                navigationType: .linkActivated
            ),
            .handleExternalApp
        )
        XCTAssertEqual(
            BrowserNavigationDestinationPolicy.decision(
                for: URL(string: "https://apps.apple.com/app/id123"),
                navigationType: .linkActivated
            ),
            .handleExternalApp
        )
    }

    func testNormalWebLinksAreAllowedWithoutManualReloading() {
        let linkedInSignIn = URL(string: "https://www.linkedin.com/login")

        XCTAssertEqual(
            BrowserNavigationDestinationPolicy.decision(
                for: linkedInSignIn,
                navigationType: .linkActivated
            ),
            .allow
        )
        XCTAssertEqual(
            BrowserNavigationDestinationPolicy.decision(
                for: linkedInSignIn,
                navigationType: .formSubmitted
            ),
            .allow
        )
        XCTAssertEqual(
            BrowserNavigationDestinationPolicy.decision(
                for: URL(string: "https://www.linkedin.com/feed#comments"),
                currentURL: URL(string: "https://www.linkedin.com/feed#top"),
                navigationType: .linkActivated
            ),
            .allow
        )
        XCTAssertEqual(
            BrowserNavigationDestinationPolicy.decision(
                for: URL(string: "about:blank"),
                navigationType: .other
            ),
            .allow
        )
    }
}

final class ExternalAppLinkPreferencesTests: XCTestCase {
    func testChoicesAreIndependentPerServiceAndPersist() {
        let suite = "ExternalAppLinkPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = ExternalAppLinkPreferences(defaults: defaults)

        preferences.setChoice(.stayInBrowser, for: "linkedin")
        preferences.setChoice(.openApp, for: "facebook")

        let restored = ExternalAppLinkPreferences(defaults: defaults)
        XCTAssertEqual(restored.choice(for: "linkedin"), .stayInBrowser)
        XCTAssertEqual(restored.choice(for: "facebook"), .openApp)
        XCTAssertNil(restored.choice(for: "instagram"))
    }

    func testChoiceCanBeChangedOrReturnedToAskNextTime() {
        let suite = "ExternalAppLinkPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = ExternalAppLinkPreferences(defaults: defaults)

        preferences.setChoice(.stayInBrowser, for: "linkedin")
        preferences.setChoice(.openApp, for: "linkedin")
        XCTAssertEqual(preferences.choice(for: "linkedin"), .openApp)

        preferences.removeChoice(for: "linkedin")
        XCTAssertNil(preferences.choice(for: "linkedin"))
    }

    func testResolverKeepsLinkedInWebSignInInBrowser() {
        XCTAssertNil(
            ExternalAppLinkResolver.request(
                for: URL(string: "https://www.linkedin.com/login"),
                sourceURL: URL(string: "https://www.linkedin.com/")
            )
        )
    }

    func testResolverCreatesServiceSpecificAppRequests() {
        let linkedIn = ExternalAppLinkResolver.request(
            for: URL(string: "linkedin://signin"),
            sourceURL: URL(string: "https://www.linkedin.com/")
        )
        let facebook = ExternalAppLinkResolver.request(
            for: URL(string: "fb://profile/123"),
            sourceURL: URL(string: "https://example.com/")
        )

        XCTAssertEqual(linkedIn?.serviceKey, "linkedin")
        XCTAssertEqual(linkedIn?.serviceName, "LinkedIn")
        XCTAssertEqual(linkedIn?.webFallbackURL, URL(string: "https://www.linkedin.com/login"))
        XCTAssertEqual(facebook?.serviceKey, "facebook")
        XCTAssertEqual(facebook?.webFallbackURL, URL(string: "https://www.facebook.com/"))
    }

    func testResolverUsesEmbeddedWebFallbackWhenAvailable() {
        let request = ExternalAppLinkResolver.request(
            for: URL(string: "linkedin://open?url=https%3A%2F%2Fwww.linkedin.com%2Fin%2Fsample-person"),
            sourceURL: nil
        )

        XCTAssertEqual(
            request?.webFallbackURL,
            URL(string: "https://www.linkedin.com/in/sample-person")
        )
    }

    func testSystemDestinationsHaveIndependentPreferenceKeys() {
        XCTAssertEqual(
            ExternalAppLinkResolver.request(
                for: URL(string: "mailto:hello@example.com"),
                sourceURL: nil
            )?.serviceKey,
            "email"
        )
        XCTAssertEqual(
            ExternalAppLinkResolver.request(
                for: URL(string: "tel:+16468014054"),
                sourceURL: nil
            )?.serviceKey,
            "phone"
        )
    }
}

final class SessionRetentionPreferencesTests: XCTestCase {
    func testKeptSessionAppliesAcrossNormalContextsForTheDomain() {
        let suite = "SessionRetentionPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = SessionRetentionPreferences(defaults: defaults)

        preferences.setKeepsSession(
            true,
            url: URL(string: "https://www.linkedin.com/login")
        )

        XCTAssertTrue(
            preferences.keepsSession(
                url: URL(string: "https://m.linkedin.com/feed")
            )
        )
        XCTAssertFalse(
            preferences.keepsSession(
                url: URL(string: "https://example.com")
            )
        )
    }

    func testKeptSessionPreferenceCanBeRemoved() {
        let suite = "SessionRetentionPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = SessionRetentionPreferences(defaults: defaults)
        let url = URL(string: "https://accounts.example.com/sign-in")

        preferences.setKeepsSession(true, url: url)
        preferences.setKeepsSession(false, url: url)

        XCTAssertFalse(preferences.keepsSession(url: url))
    }
}

final class SiteAccessibilityPreferencesTests: XCTestCase {
    func testFacebookSupportUsesOneNormalizedDomain() {
        XCTAssertEqual(
            SiteAccessibilitySupport.resolve(
                for: URL(string: "https://m.facebook.com/home")
            )?.domainKey,
            "facebook.com"
        )
        XCTAssertEqual(
            SiteAccessibilitySupport.resolve(
                for: URL(string: "https://web.facebook.com/watch")
            )?.displayName,
            "Facebook"
        )
        XCTAssertNil(
            SiteAccessibilitySupport.resolve(
                for: URL(string: "https://example.com/")
            )
        )
    }

    func testFacebookBottomNavigationPreferencePersistsAndCanBeRemoved() {
        let suite = "SiteAccessibilityPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let url = URL(string: "https://m.facebook.com/home")
        let preferences = SiteAccessibilityPreferences(defaults: defaults)

        preferences.setBottomNavigationEnabled(true, for: url)

        let restored = SiteAccessibilityPreferences(defaults: defaults)
        XCTAssertTrue(
            restored.isBottomNavigationEnabled(
                for: URL(string: "https://www.facebook.com/watch")
            )
        )

        restored.setBottomNavigationEnabled(false, for: url)
        XCTAssertFalse(
            SiteAccessibilityPreferences(defaults: defaults)
                .isBottomNavigationEnabled(for: url)
        )
    }

    func testUnsupportedSiteCannotReceiveFacebookLayoutPreference() {
        let suite = "SiteAccessibilityPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteAccessibilityPreferences(defaults: defaults)
        let url = URL(string: "https://example.com/")

        preferences.setBottomNavigationEnabled(true, for: url)

        XCTAssertFalse(preferences.isBottomNavigationEnabled(for: url))
        XCTAssertTrue(preferences.bottomNavigationDomains.isEmpty)
    }
}
