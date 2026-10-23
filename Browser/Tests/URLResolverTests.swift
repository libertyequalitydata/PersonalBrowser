import XCTest
import WebKit
@testable import PersonalBrowser

final class URLResolverTests: XCTestCase {
    func testNewTabUsesOwnerSelectedAddressPrompt() {
        XCTAssertEqual(AddressBarPresentation.newTabPlaceholder, "Enter URL or Search")
    }

    func testBlankSubtabRestoresItsQuickVisitIdentityAboveTheAddressField() {
        XCTAssertEqual(BrowserSubtabStartPresentation.systemImage, "macwindow.on.rectangle")
        XCTAssertEqual(BrowserSubtabStartPresentation.title, "Quick Visit")
        XCTAssertEqual(
            BrowserSubtabStartPresentation.subtitle,
            "Search or open a site without leaving the tab underneath."
        )
    }

    func testAddToHomeScreenRequiresSeparateEntitlementBuild() {
        XCTAssertFalse(BrowserEntitlementStatus.canAddToHomeScreen)
        XCTAssertEqual(
            BrowserEntitlementStatus.addToHomeScreenBuildFlag,
            "BrowserAddToHomeScreenEnabled"
        )
    }

    func testBrowserPasskeyAuthorizationRequiresSeparateEntitlementBuild() {
        XCTAssertFalse(BrowserPasskeySupport.isAuthorizationEnabled)
        XCTAssertEqual(
            BrowserPasskeySupport.authorizationBuildFlag,
            "BrowserPasskeyAuthorizationEnabled"
        )
    }

    func testHostAppRegistersHTTPAndHTTPSSchemes() throws {
        let urlTypes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = Set(
            urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )

        XCTAssertTrue(schemes.contains("http"))
        XCTAssertTrue(schemes.contains("https"))
    }

    func testHostAppDoesNotDeclareDefaultBrowserProhibitedPrivacyKeys() {
        let prohibitedKeys = [
            "NSPhotoLibraryUsageDescription",
            "NSLocationAlwaysUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription",
            "NSHomeKitUsageDescription",
            "NSBluetoothAlwaysUsageDescription",
            "NSHealthShareUsageDescription",
            "NSHealthUpdateUsageDescription"
        ]

        for key in prohibitedKeys {
            XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: key), "Unexpected prohibited Browser privacy key: \(key)")
        }
    }

    func testHostAppIsScopedToIPhoneForReadinessBuild() throws {
        let deviceFamilies = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int])
        XCTAssertEqual(deviceFamilies, [1])
    }

    func testHostAppMakesDownloadsVisibleInFiles() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, true)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool, true)
    }

    func testHostAppDeclaresBackgroundAudioForOwnerStartedDownloadedMedia() throws {
        let modes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        XCTAssertEqual(modes, ["audio"])
    }

    func testHostAppPrivacyManifestDeclaresAppOnlyUserDefaultsReason() throws {
        let manifestURL = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: Data(contentsOf: manifestURL),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let accessedTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = try XCTUnwrap(
            accessedTypes.first(where: {
                $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
            })
        )

        XCTAssertEqual(userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
    }

    func testPreservesExplicitHTTPSURL() {
        XCTAssertEqual(
            URLResolver.resolve("https://example.com/path?q=one")?.absoluteString,
            "https://example.com/path?q=one"
        )
    }

    func testAddsHTTPSForHost() {
        XCTAssertEqual(URLResolver.resolve("example.com")?.absoluteString, "https://example.com")
    }

    func testConvertsWordsToSearch() {
        let result = URLResolver.resolve(
            "identity containers",
            preferredLanguages: ["fi-FI", "en-US"]
        )
        let queryItems = URLComponents(
            url: try! XCTUnwrap(result),
            resolvingAgainstBaseURL: false
        )?.queryItems

        XCTAssertEqual(result?.host, "www.google.com")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "q" })?.value, "identity containers")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "hl" })?.value, "fi")
    }

    func testRejectsBlankInput() {
        XCTAssertNil(URLResolver.resolve("   "))
    }

    func testConventionalFaviconUsesPageOrigin() {
        let pageURL = URL(string: "https://www.linkedin.com/feed/update/123?tracking=true")

        XCTAssertEqual(
            URLResolver.conventionalFaviconURL(for: pageURL)?.absoluteString,
            "https://www.linkedin.com/favicon.ico"
        )
    }

    func testPinnedTabQuickSwitcherUsesShortMainDomainNames() throws {
        XCTAssertEqual(
            PinnedTabQuickSwitcherPresentation.displayName(
                for: try XCTUnwrap(URL(string: "https://www.facebook.com/groups/123"))
            ),
            "Facebook"
        )
        XCTAssertEqual(
            PinnedTabQuickSwitcherPresentation.displayName(
                for: try XCTUnwrap(URL(string: "https://news.example.co.uk/story"))
            ),
            "Example"
        )
        XCTAssertEqual(
            PinnedTabQuickSwitcherPresentation.displayName(
                for: try XCTUnwrap(URL(string: "https://my-service.fi"))
            ),
            "My Service"
        )
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.displayName(for: nil), "New Tab")
    }

    func testPinnedTabQuickSwitcherUsesCompactAdaptiveRows() {
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.columnCount, 4)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.itemWidth, 72)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.horizontalSpacing, 12)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.rowSpacing, 16)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.verticalPadding, 20)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.actionBarHeight, 52)
        XCTAssertEqual(
            PinnedTabQuickSwitcherPresentation.rows(items: [1, 2, 3, 4, 5, 6]),
            [[5, 6], [1, 2, 3, 4]]
        )
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.sheetHeight(itemCount: 1), 288)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.sheetHeight(itemCount: 4), 288)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.sheetHeight(itemCount: 5), 396)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.sheetHeight(itemCount: 9), 504)
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.sheetHeight(itemCount: 100), 640)
    }

    func testSiteLinkPolicyOnlyOverridesStandardExternalLinkActivation() throws {
        let current = try XCTUnwrap(URL(string: "https://example.com/article#one"))
        let internalLink = try XCTUnwrap(URL(string: "https://news.example.com/other"))
        let externalLink = try XCTUnwrap(URL(string: "https://destination.example/story"))
        let anchor = try XCTUnwrap(URL(string: "https://example.com/article#two"))

        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .newTab,
                sourceURL: current,
                destinationURL: externalLink,
                navigationType: .linkActivated,
                isSameDocument: false,
                shouldDownload: false
            ),
            .openNewTab
        )
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .subtab,
                sourceURL: current,
                destinationURL: externalLink,
                navigationType: .linkActivated,
                isSameDocument: false,
                shouldDownload: false
            ),
            .openSubtab
        )
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .sameTab,
                sourceURL: current,
                destinationURL: externalLink,
                navigationType: .linkActivated,
                isSameDocument: false,
                shouldDownload: false
            ),
            .loadInSameTab
        )
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .newTab,
                sourceURL: current,
                destinationURL: externalLink,
                navigationType: .formSubmitted,
                isSameDocument: false,
                shouldDownload: false
            ),
            .followWebsite
        )
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .newTab,
                sourceURL: current,
                destinationURL: externalLink,
                navigationType: .other,
                isSameDocument: false,
                shouldDownload: false
            ),
            .followWebsite
        )
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .subtab,
                sourceURL: current,
                destinationURL: externalLink,
                navigationType: .linkActivated,
                isSameDocument: false,
                shouldDownload: true
            ),
            .followWebsite
        )
        XCTAssertTrue(BrowserLinkRoutingPolicy.isSameDocument(anchor, currentURL: current))
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .newTab,
                sourceURL: current,
                destinationURL: anchor,
                navigationType: .linkActivated,
                isSameDocument: true,
                shouldDownload: false
            ),
            .followWebsite
        )
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: .subtab,
                sourceURL: current,
                destinationURL: internalLink,
                navigationType: .linkActivated,
                isSameDocument: false,
                shouldDownload: false
            ),
            .followWebsite
        )
    }

    func testLinkedInOutboundWarningResolvesItsExternalHTTPSDestination() throws {
        let source = try XCTUnwrap(URL(string: "https://www.linkedin.com/feed/"))
        let destination = try XCTUnwrap(URL(string: "https://www.cadweiser.com/toots/"))
        let wrapper = try XCTUnwrap(
            URL(string: "https://www.linkedin.com/safety/go?url=https%3A%2F%2Fwww.cadweiser.com%2Ftoots%2F&trk=feed")
        )

        XCTAssertEqual(
            SiteWrappedExternalLinkResolver.destination(for: wrapper, sourceURL: source),
            destination
        )
    }

    func testLinkedInOutboundWarningResolverIsBoundedToKnownSafeWebWrappers() throws {
        let linkedInSource = try XCTUnwrap(URL(string: "https://www.linkedin.com/feed/"))
        let unknownPath = try XCTUnwrap(
            URL(string: "https://www.linkedin.com/profile?url=https%3A%2F%2Fexample.com")
        )
        let nativeScheme = try XCTUnwrap(
            URL(string: "https://www.linkedin.com/safety/go?url=otherapp%3A%2F%2Fopen")
        )
        let nonLinkedInSource = try XCTUnwrap(URL(string: "https://example.com/article"))
        let recognizedWrapper = try XCTUnwrap(
            URL(string: "https://www.linkedin.com/redir/redirect?url=https%3A%2F%2Fdestination.example%2Fstory")
        )

        XCTAssertEqual(
            SiteWrappedExternalLinkResolver.destination(
                for: unknownPath,
                sourceURL: linkedInSource
            ),
            unknownPath
        )
        XCTAssertEqual(
            SiteWrappedExternalLinkResolver.destination(
                for: nativeScheme,
                sourceURL: linkedInSource
            ),
            nativeScheme
        )
        XCTAssertEqual(
            SiteWrappedExternalLinkResolver.destination(
                for: recognizedWrapper,
                sourceURL: nonLinkedInSource
            ),
            recognizedWrapper
        )
    }

    func testFacebookOutboundShimResolvesRealDestinationWithoutFollowingRedirectWrapper() throws {
        let source = try XCTUnwrap(URL(string: "https://www.facebook.com/groups/example"))
        let destination = try XCTUnwrap(URL(string: "https://destination.example/story"))
        let wrapper = try XCTUnwrap(
            URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fdestination.example%2Fstory&h=tracking")
        )

        XCTAssertEqual(
            SiteWrappedExternalLinkResolver.destination(for: wrapper, sourceURL: source),
            destination
        )
    }

    func testFacebookOutboundShimRejectsUnsafeOrUnrecognizedDestinations() throws {
        let source = try XCTUnwrap(URL(string: "https://m.facebook.com/"))
        let nativeDestination = try XCTUnwrap(
            URL(string: "https://lm.facebook.com/l.php?u=facebook%3A%2F%2Fopen")
        )
        let unknownWrapper = try XCTUnwrap(
            URL(string: "https://l.facebook.com/redirect?u=https%3A%2F%2Fdestination.example")
        )

        XCTAssertEqual(
            SiteWrappedExternalLinkResolver.destination(
                for: nativeDestination,
                sourceURL: source
            ),
            nativeDestination
        )
        XCTAssertEqual(
            SiteWrappedExternalLinkResolver.destination(
                for: unknownWrapper,
                sourceURL: source
            ),
            unknownWrapper
        )
    }

    func testFacebookAccessibilityFooterUsesOnlyCanonicalFacebookDestinations() {
        XCTAssertEqual(
            FacebookAccessibilityNavigation.destination(for: "home"),
            URL(string: "https://www.facebook.com/")
        )
        XCTAssertEqual(
            FacebookAccessibilityNavigation.destination(for: "friends"),
            URL(string: "https://www.facebook.com/friends/")
        )
        XCTAssertEqual(
            FacebookAccessibilityNavigation.destination(for: "video"),
            URL(string: "https://www.facebook.com/watch/")
        )
        XCTAssertEqual(
            FacebookAccessibilityNavigation.destination(for: "marketplace"),
            URL(string: "https://www.facebook.com/marketplace/")
        )
        XCTAssertEqual(
            FacebookAccessibilityNavigation.destination(for: "notifications"),
            URL(string: "https://www.facebook.com/notifications.php")
        )
        XCTAssertEqual(
            FacebookAccessibilityNavigation.destination(for: "menu"),
            URL(string: "https://www.facebook.com/?sk=bookmarks")
        )
        XCTAssertNil(FacebookAccessibilityNavigation.destination(for: "fbsbx"))
        XCTAssertNil(FacebookAccessibilityNavigation.destination(for: "https://www.fbsbx.com/"))
    }

    func testPinnedTabQuickSwitcherUsesCheckmarkSelectionInsteadOfOutline() {
        XCTAssertEqual(
            PinnedTabQuickSwitcherPresentation.selectedIndicatorSystemImage,
            "checkmark.circle.fill"
        )
    }

    func testPinnedTabQuickSwitcherUsesSaveAndMainMenuActions() {
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.title, "Pinned Tabs")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.newTabTitle, "New Tab")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.subtabTitle, "Open Subtab")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.saveTitle(isSaved: false), "Save")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.saveSystemImage(isSaved: false), "bookmark")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.saveTitle(isSaved: true), "Saved")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.saveSystemImage(isSaved: true), "bookmark.fill")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.mainMenuTitle, "Main Menu")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.mainMenuSystemImage, "ellipsis")
        XCTAssertEqual(PinnedTabQuickSwitcherPresentation.mainMenuRotationDegrees, 90)
        XCTAssertEqual(
            PinnedTabQuickSwitcherPresentation.actionOrder,
            [.menuVisibility, .save, .newTab, .subtab, .tabs, .mainMenu]
        )
    }

    func testInactiveAddressShowsCompleteHostnameWithoutURLDetails() throws {
        let url = try XCTUnwrap(
            URL(string: "https://news.eu.example.com/articles/story?q=one#details")
        )

        XCTAssertEqual(AddressBarPresentation.inactiveText(for: url), "news.eu.example.com")
    }

    func testInactiveAddressKeepsNonDefaultPortButOmitsDefaultPort() throws {
        XCTAssertEqual(
            AddressBarPresentation.inactiveText(
                for: try XCTUnwrap(URL(string: "https://example.com:8443/private"))
            ),
            "example.com:8443"
        )
        XCTAssertEqual(
            AddressBarPresentation.inactiveText(
                for: try XCTUnwrap(URL(string: "https://example.com:443/private"))
            ),
            "example.com"
        )
    }
}
