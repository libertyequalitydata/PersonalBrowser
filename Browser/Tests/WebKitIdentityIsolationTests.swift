import WebKit
import Combine
import XCTest
@testable import PersonalBrowser

@MainActor
final class WebKitIdentityIsolationTests: XCTestCase {
    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testPersistentIdentityStoresKeepCookiesIsolatedAfterRecreation() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let firstStore = WKWebsiteDataStore(forIdentifier: firstID)
        let secondStore = WKWebsiteDataStore(forIdentifier: secondID)

        defer {
            WKWebsiteDataStore.remove(forIdentifier: firstID) { _ in }
            WKWebsiteDataStore.remove(forIdentifier: secondID) { _ in }
        }

        try await setCookie(value: "personal", in: firstStore)
        try await setCookie(value: "personalbrowser", in: secondStore)

        let recreatedFirst = WKWebsiteDataStore(forIdentifier: firstID)
        let recreatedSecond = WKWebsiteDataStore(forIdentifier: secondID)
        let firstCookies = await cookies(in: recreatedFirst)
        let secondCookies = await cookies(in: recreatedSecond)

        XCTAssertEqual(cookieValue(in: firstCookies), "personal")
        XCTAssertEqual(cookieValue(in: secondCookies), "personalbrowser")
        XCTAssertNotEqual(cookieValue(in: firstCookies), cookieValue(in: secondCookies))
        XCTAssertEqual(recreatedFirst.identifier, firstID)
        XCTAssertEqual(recreatedSecond.identifier, secondID)
    }

    func testPrivateStoreHasNoPersistentIdentifier() {
        XCTAssertNil(WKWebsiteDataStore.nonPersistent().identifier)
    }

    func testMediaPlaybackRequiresOwnerActionAndStaysInline() {
        let page = WebPage(tab: BrowserTab(identityID: UUID()))
        let configuration = page.webView.configuration

        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertTrue(configuration.allowsInlineMediaPlayback)
        XCTAssertFalse(configuration.allowsPictureInPictureMediaPlayback)
    }

    func testWebpageTouchControlsDoNotShowTapOrPersistentFocusHighlights() async throws {
        let page = WebPage(tab: BrowserTab(identityID: UUID()))
        let loaded = expectation(description: "Interactive page loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }

        page.webView.loadHTMLString(
            """
            <html><body>
              <a id='link' href='https://example.com/next'>Next</a>
              <button id='button'>Back</button>
            </body></html>
            """,
            baseURL: URL(string: "https://example.com")
        )
        await fulfillment(of: [loaded], timeout: 5)

        let values = try await page.webView.evaluateJavaScript(
            """
            (() => {
              const link = document.getElementById('link');
              const button = document.getElementById('button');
              button.focus();
              return {
                linkHighlight: getComputedStyle(link).webkitTapHighlightColor,
                buttonHighlight: getComputedStyle(button).webkitTapHighlightColor,
                buttonOutline: getComputedStyle(button).outlineStyle,
                touchMode: document.documentElement.classList.contains('personalbrowser-touch-focus') ? 'true' : 'false'
              };
            })()
            """
        ) as? [String: String]

        for key in ["linkHighlight", "buttonHighlight"] {
            let highlight = values?[key] ?? ""
            XCTAssertTrue(
                ["rgba(0, 0, 0, 0)", "transparent"].contains(highlight),
                "Unexpected \(key): \(highlight)"
            )
        }
        XCTAssertEqual(values?["buttonOutline"], "none")
        XCTAssertEqual(values?["touchMode"], "true")

        let keyboardMode = try await page.webView.evaluateJavaScript(
            """
            document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
            document.documentElement.classList.contains('personalbrowser-touch-focus') ? 'touch' : 'keyboard';
            """
        ) as? String
        XCTAssertEqual(keyboardMode, "keyboard")
    }

    func testPerSiteAppPromptBlockingHidesBrandedFixedBanner() async throws {
        let suite = "AppPromptDOMTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = AppPromptPreferences(defaults: defaults)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            appPromptPreferences: preferences
        )
        let loaded = expectation(description: "App-promotion page loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }

        page.webView.loadHTMLString(
            """
            <html><body>
              <main>Article content</main>
              <section id="app-banner" style="position:fixed;bottom:0;left:0;width:100%;height:120px;background:white">
                <button>×</button>
                <strong>Use the LinkedIn app</strong>
                <button>Continue</button>
              </section>
            </body></html>
            """,
            baseURL: URL(string: "https://www.linkedin.com/feed")
        )
        await fulfillment(of: [loaded], timeout: 5)

        await page.setAppPromptBlocking(true)
        let display = try await page.webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('app-banner')).display"
        ) as? String

        XCTAssertEqual(display, "none")
        XCTAssertTrue(preferences.isBlocked(url: URL(string: "https://linkedin.com/posts/1")))
    }

    func testAppPromptBlockingHidesRepeatedLinkedInPromptsWithoutDisconnectingObserver() async throws {
        let suite = "RepeatedLinkedInPromptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            appPromptPreferences: AppPromptPreferences(defaults: defaults)
        )
        let loaded = expectation(description: "LinkedIn fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            "<html><body><main style='height:2400px'>Feed</main></body></html>",
            baseURL: URL(string: "https://www.linkedin.com/feed")
        )
        await fulfillment(of: [loaded], timeout: 5)
        await page.setAppPromptBlocking(true)

        _ = try await page.webView.evaluateJavaScript(
            """
            const first = document.createElement('section');
            first.id = 'first-promo';
            first.style = 'position:fixed;bottom:0;left:0;width:100%;height:120px';
            first.innerHTML = '<button aria-label="Close">×</button><strong>Use the LinkedIn app</strong><a href="linkedin://feed">Continue</a>';
            document.body.appendChild(first);
            true;
            """
        )
        try await Task.sleep(for: .milliseconds(450))
        let firstHidden = try await page.webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('first-promo')).display"
        ) as? String

        _ = try await page.webView.evaluateJavaScript(
            """
            const second = document.createElement('section');
            second.id = 'second-promo';
            second.style = 'position:fixed;bottom:0;left:0;width:100%;height:120px';
            second.innerHTML = '<button aria-label="Close">×</button><strong>Open in the LinkedIn app</strong><a href="linkedin://feed">Open</a>';
            document.body.appendChild(second);
            true;
            """
        )
        try await Task.sleep(for: .milliseconds(450))
        let secondHidden = try await page.webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('second-promo')).display"
        ) as? String
        let observerConnected = try await page.webView.evaluateJavaScript(
            "Boolean(window.__personalbrowserAppPromptObserver)"
        ) as? Bool

        XCTAssertEqual(firstHidden, "none")
        XCTAssertEqual(secondHidden, "none")
        XCTAssertEqual(observerConnected, true)
        await page.setAppPromptBlocking(false)
    }

    func testGmailAppPromptUsesExistingPerSiteBlocker() async throws {
        let suite = "GmailPromptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = AppPromptPreferences(defaults: defaults)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            appPromptPreferences: preferences
        )
        let loaded = expectation(description: "Gmail fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html><body><main>Inbox</main>
              <aside id="gmail-promo" role="dialog" style="position:fixed;bottom:0;left:0;width:100%;height:110px">
                <button aria-label="Close">×</button><strong>Open Gmail in the app</strong>
                <a href="https://apps.apple.com/app/gmail/id422689480">Get Gmail</a>
              </aside>
            </body></html>
            """,
            baseURL: URL(string: "https://mail.google.com/mail/u/0/")
        )
        await fulfillment(of: [loaded], timeout: 5)

        await page.setAppPromptBlocking(true)
        let display = try await page.webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('gmail-promo')).display"
        ) as? String

        XCTAssertEqual(display, "none")
        XCTAssertTrue(preferences.isBlocked(url: URL(string: "https://mail.google.com/mail/u/0/")))
    }

    func testNewTabPolicyOverridesAStandardSameFrameLinkTap() async throws {
        let suite = "WebKitExternalLinkNewTab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        preferences.setPolicy(.newTab, for: URL(string: "https://source.example/article"))
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteLinkOpeningPreferences: preferences
        )
        let loaded = expectation(description: "Policy fixture loaded")
        let opened = expectation(description: "Link requested a selected new tab")
        let expectedURL = try XCTUnwrap(URL(string: "https://destination.example/path"))
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.onOpenLinkInSelectedTab = { url in
            XCTAssertEqual(url, expectedURL)
            opened.fulfill()
        }
        page.webView.loadHTMLString(
            "<html><body><a id='destination' href='https://destination.example/path'>Open</a></body></html>",
            baseURL: URL(string: "https://source.example/article")
        )
        await fulfillment(of: [loaded], timeout: 5)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('destination').click()"
        )
        await fulfillment(of: [opened], timeout: 5)

        XCTAssertEqual(page.webView.url?.host, "source.example")
    }

    func testSubtabPolicyCreatesTemporaryRequestWithoutNavigatingSourcePage() async throws {
        let suite = "WebKitExternalLinkSubtab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        preferences.setPolicy(.subtab, for: URL(string: "https://source.example/article"))
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteLinkOpeningPreferences: preferences
        )
        let loaded = expectation(description: "Subtab policy fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            "<html><body><a id='destination' href='https://preview.example/story'>Preview</a></body></html>",
            baseURL: URL(string: "https://source.example/article")
        )
        await fulfillment(of: [loaded], timeout: 5)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('destination').click()"
        )
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(page.pendingSubtabRequest?.url, URL(string: "https://preview.example/story"))
        XCTAssertEqual(page.webView.url?.host, "source.example")
    }

    func testLinkedInOutboundWarningUsesSavedSubtabPolicyForRealDestination() async throws {
        let suite = "WebKitLinkedInOutboundSubtab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        preferences.setPolicy(.subtab, for: URL(string: "https://www.linkedin.com/feed/"))
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteLinkOpeningPreferences: preferences
        )
        let loaded = expectation(description: "LinkedIn outbound-link fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html><body>
              <a id="outbound" target="_blank"
                 href="https://www.linkedin.com/safety/go?url=https%3A%2F%2Fwww.cadweiser.com%2Ftoots%2F&amp;trk=feed">
                Open external site
              </a>
            </body></html>
            """,
            baseURL: URL(string: "https://www.linkedin.com/feed/")
        )
        await fulfillment(of: [loaded], timeout: 5)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('outbound').click()"
        )
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(
            page.pendingSubtabRequest?.url,
            URL(string: "https://www.cadweiser.com/toots/")
        )
        XCTAssertEqual(page.webView.url?.host, "www.linkedin.com")
    }

    func testFacebookJavaScriptDrivenExternalLinkUsesSavedSubtabPolicy() async throws {
        let suite = "WebKitFacebookOutboundSubtab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        preferences.setPolicy(.subtab, for: URL(string: "https://www.facebook.com/feed/"))
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteLinkOpeningPreferences: preferences
        )
        let loaded = expectation(description: "Facebook external-link fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html><body>
              <a id="outbound"
                 href="https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2Farticle%3Fsource%3Dfacebook">
                Open external site
              </a>
            </body></html>
            """,
            baseURL: URL(string: "https://www.facebook.com/feed/")
        )
        await fulfillment(of: [loaded], timeout: 5)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('outbound').click()"
        )
        try await Task.sleep(for: .milliseconds(180))

        XCTAssertEqual(
            page.pendingSubtabRequest?.url,
            URL(string: "https://example.org/article?source=facebook")
        )
        XCTAssertEqual(page.webView.url?.host, "www.facebook.com")
    }

    func testNonFacebookPageCannotInvokeFacebookExternalLinkBridge() async throws {
        let suite = "WebKitHostileBridgeInvocation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        preferences.setPolicy(.subtab, for: URL(string: "https://attacker.example/page"))
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteLinkOpeningPreferences: preferences
        )
        let loaded = expectation(description: "Non-Facebook fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html><body>
              <script>
                window.webkit.messageHandlers.browserLinkActivation.postMessage({
                  kind: 'externalURL',
                  url: 'https://destination.example/'
                });
              </script>
              Untrusted page
            </body></html>
            """,
            baseURL: URL(string: "https://attacker.example/page")
        )
        await fulfillment(of: [loaded], timeout: 5)
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(page.pendingSubtabRequest)
        XCTAssertEqual(page.webView.url?.host, "attacker.example")
    }

    func testFacebookButtonDrivenExternalNavigationUsesRecentTapForSubtabPolicy() async throws {
        let suite = "WebKitFacebookButtonOutboundSubtab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        preferences.setPolicy(.subtab, for: URL(string: "https://www.facebook.com/feed/"))
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteLinkOpeningPreferences: preferences
        )
        let loaded = expectation(description: "Facebook button-navigation fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html><body>
              <button id="outbound" onclick="
                setTimeout(() => {
                  window.location.href='https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.net%2Ffrom-button';
                }, 50);
                window.location.href='https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.net%2Ffrom-button';
              ">
                Open external site
              </button>
            </body></html>
            """,
            baseURL: URL(string: "https://www.facebook.com/feed/")
        )
        await fulfillment(of: [loaded], timeout: 5)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('outbound').click()"
        )
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(
            page.pendingSubtabRequest?.url,
            URL(string: "https://example.net/from-button")
        )
        XCTAssertEqual(page.webView.url?.host, "www.facebook.com")
        XCTAssertEqual(page.webView.url?.path, "/feed")
    }

    func testFacebookSubtabSuppressesMatchingFollowOnNavigationUnderneath() async throws {
        let suite = "WebKitFacebookDuplicateOutboundSubtab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        preferences.setPolicy(.subtab, for: URL(string: "https://www.facebook.com/feed/"))
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteLinkOpeningPreferences: preferences
        )
        let loaded = expectation(description: "Facebook duplicate-navigation fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html><head><script>
              window.addEventListener('click', event => {
                if (event.target.closest('#outbound')) {
                  setTimeout(() => {
                    window.location.href = 'https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.edu%2Fduplicate';
                  }, 40);
                }
              }, true);
            </script></head><body>
              <a id="outbound"
                 href="https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.edu%2Fduplicate">
                Open external site
              </a>
            </body></html>
            """,
            baseURL: URL(string: "https://www.facebook.com/feed/")
        )
        await fulfillment(of: [loaded], timeout: 5)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('outbound').click()"
        )
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(
            page.pendingSubtabRequest?.url,
            URL(string: "https://example.edu/duplicate")
        )
        XCTAssertEqual(page.webView.url?.host, "www.facebook.com")
        XCTAssertEqual(page.webView.url?.path, "/feed")
    }

    func testSubtabUsesTheExactParentWebsiteDataStore() throws {
        let parent = WebPage(tab: BrowserTab(identityID: UUID()))
        let subtab = BrowserSubtabPage(
            sourcePage: parent,
            url: try XCTUnwrap(URL(string: "https://example.com"))
        )

        XCTAssertTrue(
            subtab.webView.configuration.websiteDataStore ===
                parent.webView.configuration.websiteDataStore
        )
        subtab.stop()
    }

    func testSubtabInheritsTheIncognitoParentsNonPersistentWebsiteDataStore() {
        let parent = WebPage(tab: BrowserTab(identityID: nil, isPrivate: true))
        let subtab = BrowserSubtabPage(sourcePage: parent, url: nil)

        XCTAssertNil(parent.webView.configuration.websiteDataStore.identifier)
        XCTAssertTrue(
            subtab.webView.configuration.websiteDataStore ===
                parent.webView.configuration.websiteDataStore
        )
        subtab.stop()
    }

    func testSubtabReaderUsesSharedExtractionAndParentIdentityContext() async throws {
        let identityID = UUID()
        let parent = WebPage(tab: BrowserTab(identityID: identityID))
        let subtab = BrowserSubtabPage(sourcePage: parent, url: nil)
        let loaded = expectation(description: "Subtab Reader fixture loaded")
        subtab.$url
            .compactMap(\.self)
            .filter { $0.absoluteString == "https://example.com/subtab-reader" }
            .prefix(1)
            .sink { _ in loaded.fulfill() }
            .store(in: &cancellables)

        subtab.webView.loadHTMLString(
            """
            <html>
              <head>
                <title>Subtab article</title>
                <meta property="og:site_name" content="Example Reader">
              </head>
              <body>
                <article>
                  <h1>Subtab article</h1>
                  <p>The first substantial paragraph provides enough meaningful text for the shared Reader extraction path.</p>
                  <p>The second substantial paragraph confirms that the temporary Subtab can display cleaned article content.</p>
                </article>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/subtab-reader")
        )
        await fulfillment(of: [loaded], timeout: 5)

        let document = try await subtab.extractReaderDocument()

        XCTAssertEqual(document.title, "Subtab article")
        XCTAssertEqual(document.siteName, "Example Reader")
        XCTAssertTrue(document.text.contains("first substantial paragraph"))
        XCTAssertTrue(document.text.contains("second substantial paragraph"))
        XCTAssertEqual(document.capturedIdentityID, identityID)
        XCTAssertNil(parent.webView.url)
        subtab.stop()
    }

    func testRoleLabelsDoNotChangeWebsiteDataStoreOrNavigationPolicy() throws {
        let identityID = UUID()
        let source = try XCTUnwrap(URL(string: "https://notebook.google.com/"))
        let destination = try XCTUnwrap(URL(string: "https://accounts.google.com/signin"))
        let unlabeledPage = WebPage(
            tab: BrowserTab(identityID: identityID, url: source, roleIDs: [])
        )
        let labeledPage = WebPage(
            tab: BrowserTab(
                identityID: identityID,
                url: source,
                roleIDs: [UUID(), UUID()]
            )
        )

        XCTAssertEqual(
            unlabeledPage.webView.configuration.websiteDataStore.identifier,
            labeledPage.webView.configuration.websiteDataStore.identifier
        )
        XCTAssertEqual(unlabeledPage.linkOpeningPolicy, labeledPage.linkOpeningPolicy)
        XCTAssertEqual(
            BrowserLinkRoutingPolicy.action(
                for: labeledPage.linkOpeningPolicy,
                sourceURL: source,
                destinationURL: destination,
                navigationType: .other,
                isSameDocument: false,
                shouldDownload: false
            ),
            .followWebsite
        )
    }

    func testFacebookAccessibilityKeepsPageNavigationUntouchedAndAddsSpacerForNativeFooter() async throws {
        let suite = "FacebookAccessibilityWebKitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteAccessibilityPreferences(defaults: defaults)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteAccessibilityPreferences: preferences
        )
        let loaded = expectation(description: "Facebook navigation fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }

        page.webView.loadHTMLString(
            """
            <html>
              <head>
                <style>
                  body { margin: 0; min-height: 1200px; }
                  #facebook-navigation {
                    position: fixed;
                    top: 0;
                    left: 0;
                    right: 0;
                    height: 60px;
                    display: flex;
                    justify-content: space-around;
                    background: white;
                  }
                  #facebook-navigation a { display: block; width: 20%; height: 60px; }
                </style>
              </head>
              <body>
                <nav id="facebook-navigation" role="navigation">
                  <a id="home-link" aria-label="Home" href="/"><svg viewBox="0 0 24 24"><path d="M3 12h18"/></svg></a>
                  <a id="friends-link" aria-label="Friends" href="/friends"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/></svg></a>
                  <a id="watch-link" aria-label="Watch" href="/watch"><svg viewBox="0 0 24 24"><path d="M8 6v12l10-6z"/></svg></a>
                  <a id="notifications-link" aria-label="Notifications" href="/notifications"><svg viewBox="0 0 24 24"><path d="M6 18h12"/></svg></a>
                  <a id="menu-link" aria-label="Menu" href="/menu"><svg viewBox="0 0 24 24"><path d="M4 6h16"/></svg></a>
                </nav>
                <main>Feed content</main>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://www.facebook.com/")
        )
        await fulfillment(of: [loaded], timeout: 5)

        await page.setSiteBottomNavigationEnabled(true)
        let enabled = try await page.webView.evaluateJavaScript(
            """
            (() => {
              const original = document.getElementById('facebook-navigation');
              const footer = document.getElementById('personalbrowser-facebook-accessibility-footer');
              return {
                footer: Boolean(footer),
                originalLinks: original.querySelectorAll('a').length,
                originalTop: original.getBoundingClientRect().top,
                spacer: Boolean(document.getElementById('personalbrowser-facebook-bottom-navigation-spacer'))
              };
            })();
            """
        ) as? [String: Any]

        XCTAssertEqual(enabled?["footer"] as? Bool, false)
        XCTAssertEqual(enabled?["originalLinks"] as? Int, 5)
        XCTAssertEqual(try XCTUnwrap(enabled?["originalTop"] as? Double), 0, accuracy: 1)
        XCTAssertEqual(enabled?["spacer"] as? Bool, true)
        XCTAssertTrue(preferences.isBottomNavigationEnabled(for: page.webView.url))

        await page.setSiteBottomNavigationEnabled(false)
        let restored = try await page.webView.evaluateJavaScript(
            """
            (() => {
              const nav = document.getElementById('facebook-navigation');
              const rect = nav.getBoundingClientRect();
              return {
                footer: Boolean(document.getElementById('personalbrowser-facebook-accessibility-footer')),
                rectTop: rect.top,
                links: nav.querySelectorAll('a').length,
                spacer: Boolean(document.getElementById('personalbrowser-facebook-bottom-navigation-spacer'))
              };
            })();
            """
        ) as? [String: Any]

        XCTAssertEqual(restored?["footer"] as? Bool, false)
        XCTAssertEqual(try XCTUnwrap(restored?["rectTop"] as? Double), 0, accuracy: 1)
        XCTAssertEqual(restored?["links"] as? Int, 5)
        XCTAssertEqual(restored?["spacer"] as? Bool, false)
    }

    func testFacebookAccessibilityUsesNativeFooterWhenOriginalMenuIsNotDiscoverable() async throws {
        let suite = "FacebookAccessibilityFallbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteAccessibilityPreferences: SiteAccessibilityPreferences(defaults: defaults)
        )
        let loaded = expectation(description: "Facebook feed without discoverable navigation loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }

        page.webView.loadHTMLString(
            "<html><body><main>Facebook feed without a shared menu container</main></body></html>",
            baseURL: URL(string: "https://www.facebook.com/?sk=h_chr")
        )
        await fulfillment(of: [loaded], timeout: 5)

        await page.setSiteBottomNavigationEnabled(true)
        let footer = try await page.webView.evaluateJavaScript(
            """
            (() => {
              const footer = document.getElementById('personalbrowser-facebook-accessibility-footer');
              return {
                exists: Boolean(footer),
                spacer: Boolean(document.getElementById('personalbrowser-facebook-bottom-navigation-spacer'))
              };
            })();
            """
        ) as? [String: Any]

        XCTAssertEqual(footer?["exists"] as? Bool, false)
        XCTAssertEqual(footer?["spacer"] as? Bool, true)
    }

    func testFacebookAccessibilityDoesNotReplayOriginalMenuControl() async throws {
        let suite = "FacebookAccessibilityMenuButtonTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteAccessibilityPreferences: SiteAccessibilityPreferences(defaults: defaults)
        )
        let loaded = expectation(description: "Facebook button-style menu fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }

        page.webView.loadHTMLString(
            """
            <html>
              <head>
                <style>
                  body { margin: 0; min-height: 1200px; }
                  header { height: 60px; display: flex; justify-content: flex-end; }
                  #menu-button { width: 52px; height: 52px; }
                </style>
              </head>
              <body>
                <header role="navigation">
                  <div id="menu-button" role="button" aria-label="Menu" tabindex="0">
                    <svg viewBox="0 0 24 24"><path d="M4 6h16M4 12h16M4 18h16"/></svg>
                  </div>
                </header>
                <main>Feed content</main>
                <script>
                  window.__facebookOriginalMenuClicks = 0;
                  document.getElementById('menu-button').addEventListener('click', event => {
                    event.preventDefault();
                    window.__facebookOriginalMenuClicks += 1;
                  });
                </script>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://www.facebook.com/?sk=h_chr")
        )
        await fulfillment(of: [loaded], timeout: 5)

        await page.setSiteBottomNavigationEnabled(true)
        let result = try await page.webView.evaluateJavaScript(
            """
            ({
              clicks: window.__facebookOriginalMenuClicks,
              footer: Boolean(document.getElementById('personalbrowser-facebook-accessibility-footer'))
            })
            """
        ) as? [String: Any]

        XCTAssertEqual(result?["clicks"] as? Int, 0)
        XCTAssertEqual(result?["footer"] as? Bool, false)
    }

    func testFacebookAccessibilityUsesCanonicalRouteInsteadOfReplayingLinkSideEffects() async throws {
        let suite = "FacebookAccessibilityCanonicalRouteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let linkPreferences = SiteLinkOpeningPreferences(defaults: defaults)
        linkPreferences.setPolicy(
            .subtab,
            for: URL(string: "https://www.facebook.com/?sk=h_chr")
        )
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteAccessibilityPreferences: SiteAccessibilityPreferences(defaults: defaults),
            siteLinkOpeningPreferences: linkPreferences
        )
        let loaded = expectation(description: "Facebook footer side-effect fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }

        page.webView.loadHTMLString(
            """
            <html>
              <head>
                <style>
                  body { margin: 0; min-height: 1200px; }
                  nav { height: 60px; }
                  nav a { display: block; width: 52px; height: 52px; }
                </style>
              </head>
              <body>
                <nav role="navigation">
                  <a id="friends-link" aria-label="Friends" href="/friends/">Friends</a>
                </nav>
                <main>Feed content</main>
                <script>
                  document.getElementById('friends-link').addEventListener('click', event => {
                    event.preventDefault();
                    location.href = 'https://www.fbsbx.com/';
                  });
                </script>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://www.facebook.com/?sk=h_chr")
        )
        await fulfillment(of: [loaded], timeout: 5)
        page.onNavigationCommitted = nil

        await page.setSiteBottomNavigationEnabled(true)
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertNil(page.pendingSubtabRequest)
        XCTAssertNotEqual(page.webView.url?.host, "www.fbsbx.com")
        let footerExists = try await page.webView.evaluateJavaScript(
            "Boolean(document.getElementById('personalbrowser-facebook-accessibility-footer'))"
        ) as? Bool
        XCTAssertEqual(footerExists, false)
    }

    func testFacebookAccessibilityAddsVideoEscapeAndReturnsThroughSameDocumentHistory() async throws {
        let suite = "FacebookVideoEscapeHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let schemeHandler = BrowserTestURLSchemeHandler()
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteAccessibilityPreferences: SiteAccessibilityPreferences(defaults: defaults),
            testURLSchemeHandler: schemeHandler
        )
        let loaded = expectation(description: "Facebook feed fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.load(
            URLRequest(url: try XCTUnwrap(URL(string: "browser-test://www.facebook.com/")))
        )
        await fulfillment(of: [loaded], timeout: 5)
        await page.setSiteBottomNavigationEnabled(true)

        _ = try await page.webView.evaluateJavaScript(
            "history.pushState({}, '', '/reel/12345');"
        )
        try await Task.sleep(for: .milliseconds(450))

        let active = try await page.webView.evaluateJavaScript(
            """
            (() => {
              const control = document.getElementById('personalbrowser-facebook-video-escape');
              return {
                exists: Boolean(control),
                label: control?.getAttribute('aria-label') || '',
                pathname: location.pathname
              };
            })();
            """
        ) as? [String: Any]
        XCTAssertEqual(active?["exists"] as? Bool, true)
        XCTAssertEqual(active?["label"] as? String, "Back from video")
        XCTAssertEqual(active?["pathname"] as? String, "/reel/12345")

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('personalbrowser-facebook-video-escape').click();"
        )
        try await Task.sleep(for: .milliseconds(850))

        let returned = try await page.webView.evaluateJavaScript(
            """
            ({
              pathname: location.pathname,
              escapeVisible: Boolean(document.getElementById('personalbrowser-facebook-video-escape'))
            })
            """
        ) as? [String: Any]
        XCTAssertEqual(returned?["pathname"] as? String, "/")
        XCTAssertEqual(returned?["escapeVisible"] as? Bool, false)
    }

    func testFacebookAccessibilityVideoEscapeInvokesNativeDialogCloseControl() async throws {
        let suite = "FacebookVideoEscapeDialogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            siteAccessibilityPreferences: SiteAccessibilityPreferences(defaults: defaults)
        )
        let loaded = expectation(description: "Facebook dialog fixture loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            "<html><body><main style='min-height:1200px'>Feed</main></body></html>",
            baseURL: URL(string: "https://www.facebook.com/")
        )
        await fulfillment(of: [loaded], timeout: 5)
        await page.setSiteBottomNavigationEnabled(true)

        _ = try await page.webView.evaluateJavaScript(
            """
            (() => {
              window.__facebookDialogCloseClicks = 0;
              const dialog = document.createElement('section');
              dialog.id = 'video-dialog';
              dialog.setAttribute('role', 'dialog');
              dialog.setAttribute('aria-modal', 'true');
              dialog.style = 'position:fixed;inset:0;background:#000;z-index:1000';
              dialog.innerHTML = `
                <button id="native-video-close" aria-label="Close"
                        style="position:absolute;top:12px;left:12px;width:44px;height:44px">×</button>
                <video style="position:absolute;inset:0;width:100vw;height:100vh"></video>
              `;
              document.body.appendChild(dialog);
              document.getElementById('native-video-close').addEventListener('click', () => {
                window.__facebookDialogCloseClicks += 1;
                dialog.remove();
              });
              document.body.click();
            })();
            """
        )
        try await Task.sleep(for: .milliseconds(500))

        let visible = try await page.webView.evaluateJavaScript(
            "Boolean(document.getElementById('personalbrowser-facebook-video-escape'))"
        ) as? Bool
        XCTAssertEqual(visible, true)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('personalbrowser-facebook-video-escape').click();"
        )
        try await Task.sleep(for: .milliseconds(450))

        let result = try await page.webView.evaluateJavaScript(
            """
            ({
              clicks: window.__facebookDialogCloseClicks,
              dialog: Boolean(document.getElementById('video-dialog')),
              escapeVisible: Boolean(document.getElementById('personalbrowser-facebook-video-escape'))
            })
            """
        ) as? [String: Any]
        XCTAssertEqual(result?["clicks"] as? Int, 1)
        XCTAssertEqual(result?["dialog"] as? Bool, false)
        XCTAssertEqual(result?["escapeVisible"] as? Bool, false)
    }

    func testCustomAppLinkCreatesRememberableServicePromptWithoutLeavingWebPage() async throws {
        let suite = "ExternalAppLinkWebKitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = ExternalAppLinkPreferences(defaults: defaults)
        let page = WebPage(
            tab: BrowserTab(identityID: UUID()),
            externalAppLinkPreferences: preferences
        )
        let loaded = expectation(description: "LinkedIn page loaded")
        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }

        page.webView.loadHTMLString(
            """
            <html><body><a id="app-link" href="linkedin://signin">Sign in</a></body></html>
            """,
            baseURL: URL(string: "https://www.linkedin.com/")
        )
        await fulfillment(of: [loaded], timeout: 5)

        let promptReceived = expectation(description: "App-link preference prompt received")
        page.$pendingExternalAppLinkRequest
            .compactMap(\.self)
            .prefix(1)
            .sink { request in
                XCTAssertEqual(request.serviceKey, "linkedin")
                XCTAssertEqual(request.webFallbackURL, URL(string: "https://www.linkedin.com/login"))
                promptReceived.fulfill()
            }
            .store(in: &cancellables)

        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('app-link').click();"
        )
        await fulfillment(of: [promptReceived], timeout: 5)

        XCTAssertEqual(page.webView.url?.host, "www.linkedin.com")
        XCTAssertNil(preferences.choice(for: "linkedin"))
    }

    func testAppPromptMutationObserverScopesFollowUpWorkToAddedNodes() {
        let script = WebPage.enableAppPromptBlockingScript

        XCTAssertTrue(script.contains("record.addedNodes"))
        XCTAssertTrue(script.contains("if (root === document)"))
        XCTAssertTrue(script.contains("scan(document);"))
        XCTAssertTrue(script.contains("if (root.isConnected) scan(root);"))
        XCTAssertTrue(script.contains("mutationHeavyHost"))
        XCTAssertTrue(script.contains("pendingRoots.size < 12"))
        XCTAssertTrue(script.contains("mutationHeavyHost ? 300 : 100"))
        XCTAssertTrue(script.contains("const gmailHost"))
        XCTAssertTrue(script.contains("dismissControl"))
        XCTAssertFalse(script.contains("if (mutationHeavyHost) window.__personalbrowserAppPromptObserver?.disconnect()"))
        XCTAssertFalse(script.contains("document.documentElement.style.removeProperty('overflow')"))
        XCTAssertFalse(script.contains("document.body?.style.removeProperty('overflow')"))
        XCTAssertFalse(script.contains("requestAnimationFrame(() =>"))
    }

    func testWebpageTapAndScrollCanDismissAddressEditingWithoutBlockingContent() {
        let page = WebPage(tab: BrowserTab(identityID: UUID()))
        var interactionCount = 0
        page.onContentInteraction = { interactionCount += 1 }

        let contentTapGesture = page.webView.gestureRecognizers?
            .compactMap { $0 as? UITapGestureRecognizer }
            .first { $0.numberOfTouchesRequired == 1 && $0.numberOfTapsRequired == 1 }

        XCTAssertNotNil(contentTapGesture)
        XCTAssertEqual(contentTapGesture?.cancelsTouchesInView, false)
        XCTAssertEqual(page.webView.scrollView.keyboardDismissMode, .onDrag)

        page.notifyContentInteraction()
        page.scrollViewWillBeginDragging(page.webView.scrollView)

        XCTAssertEqual(interactionCount, 2)
    }

    func testWebPageInstallsOneThumbRightEdgeQuickSwitcherGesture() {
        let page = WebPage(tab: BrowserTab(identityID: UUID(), browserControlsHidden: true))
        let edgeGesture = page.webView.gestureRecognizers?
            .compactMap { $0 as? UIScreenEdgePanGestureRecognizer }
            .first { $0.edges == .right }

        XCTAssertNotNil(edgeGesture)
        XCTAssertEqual(edgeGesture?.minimumNumberOfTouches, 1)
        XCTAssertEqual(edgeGesture?.maximumNumberOfTouches, 1)
        XCTAssertEqual(edgeGesture?.cancelsTouchesInView, true)
    }

    func testLoadedPageSuppliesTabVisualIdentityMetadata() async throws {
        let tab = BrowserTab(identityID: UUID())
        let page = WebPage(tab: tab)
        let metadataReceived = expectation(description: "Page metadata extracted")

        page.onNavigationCommitted = { url, title, metadata in
            XCTAssertEqual(url.absoluteString, "https://example.com/articles/story")
            XCTAssertEqual(title, "Example story")
            XCTAssertEqual(metadata.siteName, "Example News")
            XCTAssertEqual(metadata.faviconURL?.absoluteString, "https://example.com/favicon.png")
            XCTAssertEqual(metadata.previewImageURL?.absoluteString, "https://example.com/images/social-card.jpg")
            metadataReceived.fulfill()
        }

        page.webView.loadHTMLString(
            """
            <html>
              <head>
                <title>Example story</title>
                <meta property="og:site_name" content="Example News">
                <meta property="og:image" content="/images/social-card.jpg">
                <link rel="icon" href="/favicon.png">
              </head>
              <body><article>Story</article></body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/articles/story")
        )

        await fulfillment(of: [metadataReceived], timeout: 5)

        let readerDocument = try await page.extractReaderDocument(identityID: tab.identityID)
        XCTAssertEqual(readerDocument.previewImageURL?.absoluteString, "https://example.com/images/social-card.jpg")
    }

    func testReaderExtractionKeepsArticleAndHeroWhileRemovingPageClutter() async throws {
        let tab = BrowserTab(identityID: UUID())
        let page = WebPage(tab: tab)
        let loaded = expectation(description: "Article loaded")

        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html>
              <head>
                <title>Site shell title</title>
                <meta property="og:title" content="A focused story">
                <meta property="og:site_name" content="Example Journal">
                <meta property="og:image" content="/images/social-card.jpg">
              </head>
              <body>
                <nav>Home Products Pricing Careers Sign in</nav>
                <article class="analytics-widget" style="display: none">
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                  Hidden recommendation and analytics payload. Hidden recommendation and analytics payload.
                </article>
                <main>
                  <article class="story-content">
                    <h1>A focused story</h1>
                    <img class="hero" src="/images/article-hero.jpg" width="1200" height="700">
                    <p>The first substantial paragraph explains the essential subject in enough detail for article extraction.</p>
                    <p>The second substantial paragraph continues the argument and belongs in the clean reading view.</p>
                    <aside>Sponsored offer and newsletter signup</aside>
                    <section class="related-stories">Related story one Related story two</section>
                  </article>
                  <section class="comments">Comments and replies should not appear in Reader.</section>
                </main>
                <footer>Privacy Terms Contact</footer>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/articles/focused-story")
        )

        await fulfillment(of: [loaded], timeout: 5)

        let document = try await page.extractReaderDocument(identityID: tab.identityID)

        XCTAssertEqual(document.title, "A focused story")
        XCTAssertEqual(document.siteName, "Example Journal")
        XCTAssertEqual(document.previewImageURL?.absoluteString, "https://example.com/images/article-hero.jpg")
        XCTAssertTrue(document.text.contains("first substantial paragraph"))
        XCTAssertTrue(document.text.contains("second substantial paragraph"))
        XCTAssertFalse(document.text.contains("Home Products Pricing"))
        XCTAssertFalse(document.text.contains("Related story"))
        XCTAssertFalse(document.text.contains("Comments and replies"))
        XCTAssertFalse(document.text.contains("Sponsored offer"))
        XCTAssertFalse(document.text.contains("Hidden recommendation"))
    }

    func testReaderExtractionDoesNotTreatAHomepageIndexAsAnArticle() async throws {
        let tab = BrowserTab(identityID: UUID())
        let page = WebPage(tab: tab)
        let loaded = expectation(description: "Index loaded")

        page.onNavigationCommitted = { _, _, _ in loaded.fulfill() }
        page.webView.loadHTMLString(
            """
            <html>
              <head><title>Example News</title></head>
              <body>
                <main class="main-content">
                  <a href="/one">First headline and a short teaser for the first news item</a>
                  <a href="/two">Second headline and a short teaser for the second news item</a>
                  <a href="/three">Third headline and a short teaser for the third news item</a>
                  <a href="/four">Fourth headline and a short teaser for the fourth news item</a>
                </main>
              </body>
            </html>
            """,
            baseURL: URL(string: "https://example.com/")
        )

        await fulfillment(of: [loaded], timeout: 5)

        let document = try await page.extractReaderDocument(identityID: tab.identityID)

        XCTAssertEqual(document.captureKind, .referenceOnly)
        XCTAssertEqual(
            document.text,
            "A readable local capture was not available. The source reference is retained."
        )
    }

    func testSameDocumentNavigationPublishesFullURLAndBackState() async throws {
        let tab = BrowserTab(identityID: UUID())
        let schemeHandler = BrowserTestURLSchemeHandler()
        let page = WebPage(tab: tab, testURLSchemeHandler: schemeHandler)
        let initialLoaded = expectation(description: "Initial page loaded")
        let initialURL = "browser-test://example/start"

        page.onNavigationCommitted = { url, _, _ in
            if url.absoluteString == initialURL {
                initialLoaded.fulfill()
            }
        }
        page.webView.load(URLRequest(url: try XCTUnwrap(URL(string: initialURL))))
        await fulfillment(of: [initialLoaded], timeout: 5)

        let routedURL = "browser-test://example/articles/full-path?source=browser#details"
        let routeObserved = expectation(description: "Same-document route observed")
        page.$url
            .compactMap(\.self)
            .filter { $0.absoluteString == routedURL }
            .prefix(1)
            .sink { _ in routeObserved.fulfill() }
            .store(in: &cancellables)

        _ = try await page.webView.evaluateJavaScript(
            "history.pushState({}, '', '/articles/full-path?source=browser#details'); document.title = 'Full path';"
        )
        await fulfillment(of: [routeObserved], timeout: 5)

        XCTAssertEqual(page.url?.absoluteString, routedURL)
        XCTAssertTrue(page.canGoBack)

        let backObserved = expectation(description: "Back navigation observed")
        page.$url
            .compactMap(\.self)
            .filter { $0.absoluteString == initialURL }
            .prefix(1)
            .sink { _ in backObserved.fulfill() }
            .store(in: &cancellables)

        page.goBack()
        await fulfillment(of: [backObserved], timeout: 5)

        XCTAssertEqual(page.url?.absoluteString, initialURL)
        XCTAssertTrue(page.canGoForward)
    }

    private func setCookie(value: String, in store: WKWebsiteDataStore) async throws {
        guard let cookie = HTTPCookie(properties: [
            .domain: "browser-identity.test",
            .path: "/",
            .name: "browser_identity",
            .value: value,
            .secure: "TRUE"
        ]) else {
            XCTFail("Could not create test cookie")
            return
        }

        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func cookies(in store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func cookieValue(in cookies: [HTTPCookie]) -> String? {
        cookies.first(where: { $0.name == "browser_identity" })?.value
    }
}

private final class BrowserTestURLSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let data = Data(
            "<html><head><title>Test page</title></head><body>Test page</body></html>".utf8
        )
        let response = URLResponse(
            url: url,
            mimeType: "text/html",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
