import Foundation
import Combine
import UIKit
import WebKit

enum QuickSwitcherEdgeSwipePolicy {
    static let minimumDistance: CGFloat = 52

    static func canBegin(controlsHidden: Bool, velocity: CGPoint) -> Bool {
        controlsHidden
            && velocity.x < 0
            && abs(velocity.x) > abs(velocity.y) * 1.2
    }

    static func shouldOpen(translation: CGPoint) -> Bool {
        translation.x <= -minimumDistance
            && abs(translation.x) > abs(translation.y) * 1.2
    }
}

enum BrowserNavigationDestinationPolicy {
    enum Decision: Equatable {
        case allow
        case handleExternalApp
    }

    private static let browserInternalSchemes: Set<String> = [
        "about", "blob", "data", "javascript", "browser-test"
    ]

    static func decision(
        for url: URL?,
        currentURL: URL? = nil,
        navigationType: WKNavigationType
    ) -> Decision {
        guard let url, let scheme = url.scheme?.lowercased() else { return .allow }

        if ["http", "https"].contains(scheme) {
            return ExternalAppLinkResolver.request(for: url, sourceURL: currentURL) == nil
                ? .allow
                : .handleExternalApp
        }
        if browserInternalSchemes.contains(scheme) {
            return .allow
        }
        return .handleExternalApp
    }
}

enum BrowserLinkRoutingAction: Equatable {
    case followWebsite
    case loadInSameTab
    case openNewTab
    case openSubtab
}

private struct FacebookExternalLinkRoutingRecord {
    let sourceURL: URL?
    let requestedURL: URL
    let destinationURL: URL
    let handledAt: Date
}

enum BrowserLinkRoutingPolicy {
    static func action(
        for policy: BrowserLinkOpeningPolicy,
        sourceURL: URL?,
        destinationURL: URL?,
        navigationType: WKNavigationType,
        isSameDocument: Bool,
        shouldDownload: Bool
    ) -> BrowserLinkRoutingAction {
        guard navigationType == .linkActivated,
              !isSameDocument,
              !shouldDownload,
              SiteLinkOpeningPreferences.isExternalLink(
                from: sourceURL,
                to: destinationURL
              ) else { return .followWebsite }

        switch policy {
        case .followWebsite: return .followWebsite
        case .sameTab: return .loadInSameTab
        case .newTab: return .openNewTab
        case .subtab: return .openSubtab
        }
    }

    static func isSameDocument(_ destination: URL, currentURL: URL?) -> Bool {
        guard let currentURL,
              var destinationComponents = URLComponents(
                url: destination,
                resolvingAgainstBaseURL: false
              ),
              var currentComponents = URLComponents(
                url: currentURL,
                resolvingAgainstBaseURL: false
              ) else { return false }
        destinationComponents.fragment = nil
        currentComponents.fragment = nil
        return destinationComponents == currentComponents
    }
}

@MainActor
final class WebPage: NSObject, ObservableObject {
    let tabID: UUID
    let webView: WKWebView
    let chromeBars = ChromeBarsModel()
    private var chromeBarsCancellable: AnyCancellable?
    private var webViewObservations: [NSKeyValueObservation] = []
    private let historyMessageHandler: BrowserHistoryScriptMessageHandler
    private let linkActivationMessageHandler: BrowserLinkActivationScriptMessageHandler
    private let appPromptPreferences: AppPromptPreferences
    private let siteLinkOpeningPreferences: SiteLinkOpeningPreferences
    let externalAppLinkPreferences: ExternalAppLinkPreferences
    let siteAccessibilityPreferences: SiteAccessibilityPreferences
    private let sessionRetentionPreferences: SessionRetentionPreferences
    private let isPrivateSession: Bool
    private let identityID: UUID?
    private let downloadDirectory: URL
    private var dismissedSignInHosts = Set<String>()
    private var activeDownloads: [UUID: WKDownload] = [:]
    private var downloadIDs: [ObjectIdentifier: UUID] = [:]
    private var downloadObservations: [UUID: NSKeyValueObservation] = [:]
    private var downloadFilenames: [UUID: String] = [:]
    private var retryDownloadRecords: [UUID: BrowserDownloadRecord] = [:]
    private var resumedRetryIDs = Set<UUID>()
    private var latestPageMetadata = PageVisualMetadata()
    private var downloadNoticeTask: Task<Void, Never>?
    private var sameDocumentHistoryDepth = 0
    private var allowedExternalWebURLOnce: URL?
    private var lastFacebookUserActivationAt: Date?
    private var recentlyRoutedFacebookExternalLink: FacebookExternalLinkRoutingRecord?
    private lazy var quickSwitcherEdgeGesture = UIScreenEdgePanGestureRecognizer(
        target: self,
        action: #selector(handleQuickSwitcherEdgeSwipe(_:))
    )

    @Published private(set) var url: URL?
    @Published private(set) var title = "New Tab"
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var chromeProgress: CGFloat = 1
    @Published private(set) var blocksAppPrompts = false
    @Published private(set) var usesSiteBottomNavigation = false
    @Published private(set) var browserControlsPinnedHidden = false
    @Published private(set) var linkOpeningPolicy: BrowserLinkOpeningPolicy
    @Published private(set) var signInOfferHost: String?
    @Published private(set) var downloadNotice: BrowserDownloadNotice?
    @Published var pendingExternalAppLinkRequest: ExternalAppLinkRequest?
    @Published var pendingSubtabRequest: BrowserSubtabRequest?
    @Published var errorMessage: String?

    var presentableErrorMessage: String? {
        guard let errorMessage,
              !BrowserDownloadInterruption.matches(errorMessage) else { return nil }
        return errorMessage
    }

    var readerIdentityID: UUID? { identityID }

    var onNavigationCommitted: ((URL, String, PageVisualMetadata) -> Void)?
    var onOpenNewTab: ((URL) -> Void)?
    var onOpenLinkInNewTab: ((URL) -> Void)?
    var onOpenLinkInSelectedTab: ((URL) -> Void)?
    var onOpenLinkInIncognito: ((URL) -> Void)?
    var onAddLinkToReadingList: ((URL) -> Void)?
    var onDownloadStarted: ((BrowserDownloadRecord) -> Void)?
    var onDownloadProgress: ((UUID, Double) -> Void)?
    var onDownloadFinished: ((UUID, Int64?, Date) -> Void)?
    var onDownloadFailed: ((UUID, String, Bool, Data?) -> Void)?
    var onContentInteraction: (() -> Void)?
    var onQuickSwitcherRequested: (() -> Void)?
    var onBrowserControlsHiddenChanged: ((Bool) -> Void)?

    init(
        tab: BrowserTab,
        appPromptPreferences: AppPromptPreferences = .shared,
        externalAppLinkPreferences: ExternalAppLinkPreferences = .shared,
        siteAccessibilityPreferences: SiteAccessibilityPreferences = .shared,
        siteLinkOpeningPreferences: SiteLinkOpeningPreferences = .shared,
        sessionRetentionPreferences: SessionRetentionPreferences = .shared,
        downloadDirectory: URL = BrowserDownloadSupport.downloadsDirectory(),
        testURLSchemeHandler: WKURLSchemeHandler? = nil
    ) {
        tabID = tab.id
        self.appPromptPreferences = appPromptPreferences
        self.siteLinkOpeningPreferences = siteLinkOpeningPreferences
        self.externalAppLinkPreferences = externalAppLinkPreferences
        self.siteAccessibilityPreferences = siteAccessibilityPreferences
        self.sessionRetentionPreferences = sessionRetentionPreferences
        isPrivateSession = tab.isPrivate
        identityID = tab.identityID
        linkOpeningPolicy = siteLinkOpeningPreferences.policy(for: tab.url)
        self.downloadDirectory = downloadDirectory
        let configuration = WKWebViewConfiguration()
        let historyMessageHandler = BrowserHistoryScriptMessageHandler()
        self.historyMessageHandler = historyMessageHandler
        let linkActivationMessageHandler = BrowserLinkActivationScriptMessageHandler()
        self.linkActivationMessageHandler = linkActivationMessageHandler
        if tab.isPrivate {
            configuration.websiteDataStore = .nonPersistent()
        } else if let identityID = tab.identityID {
            configuration.websiteDataStore = .init(forIdentifier: identityID)
        } else {
            configuration.websiteDataStore = .default()
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        if let testURLSchemeHandler {
            configuration.setURLSchemeHandler(testURLSchemeHandler, forURLScheme: "browser-test")
        }
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.historyObservationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.interactionHighlightScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.facebookExternalLinkActivationScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(
            historyMessageHandler,
            name: BrowserHistoryScriptMessageHandler.messageName
        )
        configuration.userContentController.add(
            linkActivationMessageHandler,
            name: BrowserLinkActivationScriptMessageHandler.messageName
        )
        webView = WKWebView(frame: UIScreen.main.bounds, configuration: configuration)
        super.init()
        historyMessageHandler.onMessage = { [weak self] kind, fallbackURL in
            Task { @MainActor [weak self] in
                self?.handleSameDocumentNavigation(kind: kind, fallbackURL: fallbackURL)
            }
        }
        linkActivationMessageHandler.onActivation = { [weak self] requestedURL in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let requestedURL {
                    self.lastFacebookUserActivationAt = nil
                    self.handleDeliberateExternalLink(requestedURL)
                } else {
                    self.lastFacebookUserActivationAt = Date()
                }
            }
        }
        chromeBarsCancellable = chromeBars.$progress.sink { [weak self] progress in
            self?.chromeProgress = progress
        }
        if tab.keepsBrowserControlsHidden {
            browserControlsPinnedHidden = true
            chromeBars.hideUntilRevealed(animated: false)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.delegate = self
        webView.scrollView.keyboardDismissMode = .onDrag
        webView.allowsBackForwardNavigationGestures = true
        observeWebViewState()
        let revealControlsGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTwoFingerTap)
        )
        revealControlsGesture.numberOfTouchesRequired = 2
        revealControlsGesture.numberOfTapsRequired = 1
        revealControlsGesture.cancelsTouchesInView = false
        revealControlsGesture.delegate = self
        webView.addGestureRecognizer(revealControlsGesture)
        quickSwitcherEdgeGesture.edges = .right
        quickSwitcherEdgeGesture.minimumNumberOfTouches = 1
        quickSwitcherEdgeGesture.maximumNumberOfTouches = 1
        quickSwitcherEdgeGesture.cancelsTouchesInView = true
        quickSwitcherEdgeGesture.delegate = self
        webView.addGestureRecognizer(quickSwitcherEdgeGesture)
        let dismissAddressEditingGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handleContentTap)
        )
        dismissAddressEditingGesture.numberOfTouchesRequired = 1
        dismissAddressEditingGesture.numberOfTapsRequired = 1
        dismissAddressEditingGesture.cancelsTouchesInView = false
        dismissAddressEditingGesture.delaysTouchesBegan = false
        dismissAddressEditingGesture.delaysTouchesEnded = false
        dismissAddressEditingGesture.delegate = self
        webView.addGestureRecognizer(dismissAddressEditingGesture)
        if let url = tab.url {
            load(url)
        }
    }

    func load(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            errorMessage = "Browser can open HTTP and HTTPS addresses only."
            return
        }
        errorMessage = nil
        webView.load(BrowserLanguage.request(for: url))
    }

    func goBack() {
        if sameDocumentHistoryDepth > 0 {
            webView.evaluateJavaScript("history.back()")
        } else if webView.canGoBack {
            webView.goBack()
        }
    }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    @discardableResult
    func cancelDownload(_ id: UUID) -> Bool {
        guard let download = activeDownloads[id] else { return false }
        download.cancel { [weak self] resumeData in
            guard let self else { return }
            self.cleanupDownload(id)
            self.onDownloadFailed?(id, "Download cancelled.", true, resumeData)
            self.showDownloadNotice("Download cancelled", systemImage: "xmark.circle")
        }
        return true
    }

    @discardableResult
    func retryDownload(_ record: BrowserDownloadRecord, resumeData: Data?) -> Bool {
        guard ["http", "https"].contains(record.sourceURL.scheme?.lowercased() ?? "") else {
            return false
        }
        retryDownloadRecords[record.id] = record
        if let resumeData {
            resumedRetryIDs.insert(record.id)
            webView.resumeDownload(fromResumeData: resumeData) { [weak self] download in
                self?.register(download, id: record.id)
            }
        } else {
            startFreshRetry(record)
        }
        return true
    }

    private func startFreshRetry(_ record: BrowserDownloadRecord) {
        retryDownloadRecords[record.id] = record
        webView.startDownload(using: BrowserLanguage.request(for: record.sourceURL)) { [weak self] download in
            self?.register(download, id: record.id)
        }
    }

    func hideBrowserControls() {
        guard !browserControlsPinnedHidden else { return }
        browserControlsPinnedHidden = true
        chromeBars.hideUntilRevealed()
        onBrowserControlsHiddenChanged?(true)
    }

    func revealBrowserControls() {
        guard browserControlsPinnedHidden else { return }
        browserControlsPinnedHidden = false
        chromeBars.reveal()
        onBrowserControlsHiddenChanged?(false)
    }

    func refreshLinkOpeningPolicy() {
        linkOpeningPolicy = siteLinkOpeningPreferences.policy(for: webView.url ?? url)
        updateInjectedLinkOpeningPolicy()
    }

    func openSubtab(_ url: URL? = nil) {
        pendingSubtabRequest = BrowserSubtabRequest(url: url)
    }

    func dismissSubtab() {
        pendingSubtabRequest = nil
    }

    func setAppPromptBlocking(_ blocked: Bool) async {
        guard webView.url?.host != nil else { return }
        appPromptPreferences.setBlocked(blocked, url: webView.url)
        blocksAppPrompts = blocked

        do {
            if blocked {
                _ = try await webView.evaluateJavaScript(Self.enableAppPromptBlockingScript)
            } else {
                _ = try await webView.evaluateJavaScript(Self.disableAppPromptBlockingScript)
            }
        } catch {
            errorMessage = "The app-prompt preference was saved, but this page could not be updated until it is reloaded."
        }
    }

    var siteAccessibilitySupport: SiteAccessibilitySupport? {
        SiteAccessibilitySupport.resolve(for: webView.url ?? url)
    }

    func setSiteBottomNavigationEnabled(_ enabled: Bool) async {
        guard let pageURL = webView.url ?? url,
              SiteAccessibilitySupport.resolve(for: pageURL)?.supportsBottomNavigation == true else {
            return
        }

        siteAccessibilityPreferences.setBottomNavigationEnabled(enabled, for: pageURL)
        usesSiteBottomNavigation = enabled

        do {
            _ = try await webView.evaluateJavaScript(
                enabled
                    ? Self.enableFacebookBottomNavigationScript
                    : Self.disableFacebookBottomNavigationScript
            )
        } catch {
            errorMessage = enabled
                ? "The accessibility preference was saved and will be applied after this page reloads."
                : "The accessibility preference was removed and the original layout will return after this page reloads."
        }
    }

    func navigateFacebookAccessibilityFooter(to destination: FacebookAccessibilityDestination) {
        guard usesSiteBottomNavigation,
              siteAccessibilitySupport?.domainKey == "facebook.com" else { return }
        webView.load(BrowserLanguage.request(for: destination.url))
    }

    func chooseExternalAppLink(
        _ choice: ExternalAppLinkChoice,
        request: ExternalAppLinkRequest
    ) {
        if pendingExternalAppLinkRequest?.id == request.id {
            pendingExternalAppLinkRequest = nil
        }
        externalAppLinkPreferences.setChoice(choice, for: request.serviceKey)
        applyExternalAppLinkChoice(choice, request: request)
    }

    func dismissExternalAppLinkRequest() {
        pendingExternalAppLinkRequest = nil
    }

    @discardableResult
    private func handleExternalAppLink(_ destinationURL: URL) -> Bool {
        guard let request = ExternalAppLinkResolver.request(
            for: destinationURL,
            sourceURL: webView.url
        ) else { return false }

        if let choice = externalAppLinkPreferences.choice(for: request.serviceKey) {
            applyExternalAppLinkChoice(choice, request: request)
        } else if pendingExternalAppLinkRequest?.serviceKey != request.serviceKey {
            pendingExternalAppLinkRequest = request
        }
        return true
    }

    private func applyExternalAppLinkChoice(
        _ choice: ExternalAppLinkChoice,
        request: ExternalAppLinkRequest
    ) {
        switch choice {
        case .stayInBrowser:
            guard let fallback = request.webFallbackURL,
                  fallback != webView.url else { return }
            if ExternalAppLinkResolver.request(for: fallback, sourceURL: webView.url) != nil {
                allowedExternalWebURLOnce = fallback
            }
            load(fallback)
        case .openApp:
            UIApplication.shared.open(request.destinationURL) { [weak self] opened in
                guard !opened else { return }
                Task { @MainActor [weak self] in
                    self?.errorMessage = "\(request.serviceName) could not be opened. You can change this choice in App Link Preferences."
                }
            }
        }
    }

    func keepSignInSession() {
        sessionRetentionPreferences.setKeepsSession(true, url: webView.url)
        signInOfferHost = nil
    }

    func dismissSignInOffer() {
        if let host = signInOfferHost {
            dismissedSignInHosts.insert(host)
        }
        signInOfferHost = nil
    }

    func extractReaderDocument(identityID: UUID?) async throws -> ReaderDocument {
        try await Self.extractReaderDocument(
            from: webView,
            fallbackTitle: title,
            identityID: identityID
        )
    }

    static func extractReaderDocument(
        from webView: WKWebView,
        fallbackTitle: String,
        identityID: UUID?
    ) async throws -> ReaderDocument {
        guard let sourceURL = webView.url else { throw ReaderError.noPage }

        let script = #"""
        (() => {
          const normalizeInline = value => String(value || '')
            .replace(/\s+/g, ' ')
            .trim();
          const normalizeArticleText = value => String(value || '')
            .replace(/\r/g, '')
            .replace(/[ \t]+\n/g, '\n')
            .replace(/\n[ \t]+/g, '\n')
            .replace(/[ \t]{2,}/g, ' ')
            .replace(/\n{3,}/g, '\n\n')
            .trim();
          const absoluteURL = value => {
            if (!value) return null;
            try {
              const url = new URL(value, document.baseURI);
              return /^https?:$/.test(url.protocol) ? url.href : null;
            } catch (_) {
              return null;
            }
          };
          const firstValue = value => Array.isArray(value) ? value[0] : value;
          const imageValue = value => {
            const candidate = firstValue(value);
            if (typeof candidate === 'string') return candidate;
            if (candidate && typeof candidate === 'object') {
              return candidate.contentUrl || candidate.url || candidate['@id'] || null;
            }
            return null;
          };
          const authorValue = value => {
            const values = Array.isArray(value) ? value : [value];
            return values
              .map(author => typeof author === 'string' ? author : author?.name)
              .filter(Boolean)
              .join(', ') || null;
          };
          const articleTypes = new Set([
            'Article', 'NewsArticle', 'BlogPosting', 'Report', 'TechArticle',
            'ScholarlyArticle', 'SocialMediaPosting'
          ]);
          const structuredItems = [];
          const collectStructuredItems = value => {
            if (!value) return;
            if (Array.isArray(value)) {
              value.forEach(collectStructuredItems);
              return;
            }
            if (typeof value !== 'object') return;
            structuredItems.push(value);
            if (value['@graph']) collectStructuredItems(value['@graph']);
          };
          document.querySelectorAll('script[type="application/ld+json"]').forEach(script => {
            try { collectStructuredItems(JSON.parse(script.textContent || '')); } catch (_) {}
          });
          const structuredArticle = structuredItems
            .filter(item => {
              const types = Array.isArray(item['@type']) ? item['@type'] : [item['@type']];
              return types.some(type => articleTypes.has(type));
            })
            .sort((left, right) =>
              String(right.articleBody || '').length - String(left.articleBody || '').length
            )[0] || null;

          const negativePattern = /(^|[-_\s])(ad|ads|advert|banner|breadcrumb|comment|cookie|footer|header|login|menu|nav|newsletter|outbrain|popup|promo|recommend|related|reply|share|sharing|sidebar|signup|sponsor|subscribe|toolbar)([-_\s]|$)/i;
          const positivePattern = /(^|[-_\s])(article|body|content|entry|main|post|story|text)([-_\s]|$)/i;
          const nodeSignature = node => `${node.id || ''} ${typeof node.className === 'string' ? node.className : ''}`;
          const linkDensity = node => {
            const textLength = normalizeInline(node.textContent).length || 1;
            const linkLength = [...node.querySelectorAll('a')]
              .reduce((sum, link) => sum + normalizeInline(link.textContent).length, 0);
            return linkLength / textLength;
          };
          const candidateScore = node => {
            // Reader content must be visibly rendered. Some sites place large analytics or
            // recommendation payloads in display:none <article> nodes; textContent would make
            // those invisible nodes outrank the real article body.
            const text = normalizeInline(node.innerText);
            if (text.length < 160) return -Infinity;
            const paragraphs = [...node.querySelectorAll('p')]
              .filter(paragraph => normalizeInline(paragraph.textContent).length >= 40);
            const density = linkDensity(node);
            if (paragraphs.length === 0 && density > 0.55) return -Infinity;
            const punctuation = (text.match(/[.!?](?:\s|$)/g) || []).length;
            const signature = nodeSignature(node);
            let score = Math.min(text.length, 14000)
              + Math.min(paragraphs.length, 40) * 180
              + Math.min(punctuation, 120) * 18
              - density * Math.min(text.length, 14000) * 2.2;
            if (node.tagName === 'ARTICLE') score += 3600;
            if (node.tagName === 'MAIN' || node.getAttribute('role') === 'main') score += 1800;
            if (positivePattern.test(signature)) score += 1300;
            if (negativePattern.test(signature)) score -= 5000;
            return score;
          };

          const candidateSet = new Set(document.querySelectorAll(
            'article, main, [role="main"], [itemprop="articleBody"], ' +
            '[class*="article"], [class*="story"], [class*="post-content"], [class*="entry-content"]'
          ));
          document.querySelectorAll('p').forEach(paragraph => {
            if (normalizeInline(paragraph.textContent).length < 80) return;
            const parent = paragraph.closest('article, main, [role="main"], section, div');
            if (parent) candidateSet.add(parent);
          });
          const bestCandidate = [...candidateSet]
            .map(node => ({ node, score: candidateScore(node) }))
            .sort((left, right) => right.score - left.score)[0] || null;
          const root = bestCandidate && bestCandidate.score >= 1800
            ? bestCandidate.node
            : document.createElement('main');

          const bestContentImage = container => {
            const candidates = [...(container?.querySelectorAll('img') || [])]
              .map((image, index) => {
                const source = image.currentSrc || image.getAttribute('src') ||
                  image.getAttribute('data-src') || image.getAttribute('data-original');
                const width = image.naturalWidth || Number(image.getAttribute('width')) || 0;
                const height = image.naturalHeight || Number(image.getAttribute('height')) || 0;
                const signature = `${nodeSignature(image)} ${image.getAttribute('alt') || ''}`;
                if (!absoluteURL(source) || width < 240 || height < 140 ||
                    /(avatar|badge|emoji|icon|logo|profile|sprite)/i.test(signature)) return null;
                const aspect = width / Math.max(height, 1);
                if (aspect > 4.5 || aspect < 0.35) return null;
                let score = Math.min(width * height, 1600000);
                if (image.closest('figure, picture')) score += 180000;
                if (/(feature|hero|lead|main)/i.test(signature)) score += 220000;
                score -= index * 12000;
                return { url: absoluteURL(source), score };
              })
              .filter(Boolean)
              .sort((left, right) => right.score - left.score);
            return candidates[0]?.url || null;
          };

          const clone = root.cloneNode(true);
          clone.querySelectorAll(
            'script, style, noscript, iframe, canvas, svg, form, button, input, select, textarea, ' +
            'nav, footer, aside, header, [role="navigation"], [role="complementary"], ' +
            '[aria-hidden="true"], [hidden]'
          ).forEach(node => node.remove());
          [...clone.querySelectorAll('*')].forEach(node => {
            const signature = nodeSignature(node);
            const text = normalizeInline(node.textContent);
            if (negativePattern.test(signature) ||
                (/^(like|comment|share|follow|repost)(\s|$)/i.test(text) && text.length < 120) ||
                (['DIV', 'SECTION', 'UL', 'OL'].includes(node.tagName) &&
                  text.length < 800 && linkDensity(node) > 0.55)) {
              node.remove();
            }
          });

          const metadataTitle = structuredArticle?.headline || structuredArticle?.name ||
            document.querySelector('meta[property="og:title"]')?.content ||
            document.querySelector('h1')?.textContent || document.title || location.hostname;
          const title = normalizeInline(metadataTitle);
          const seenBlocks = new Set();
          const contentBlocks = [...clone.querySelectorAll('h2, h3, h4, p, blockquote, pre, li')]
            .map(node => normalizeArticleText(node.innerText || node.textContent))
            .filter(text => {
              if (text.length < 24) return false;
              const key = normalizeInline(text).toLowerCase();
              if (!key || key === title.toLowerCase() || seenBlocks.has(key)) return false;
              seenBlocks.add(key);
              return true;
            });
          const structuredBody = normalizeArticleText(structuredArticle?.articleBody || '');
          let text = structuredBody.length >= 200
            ? structuredBody
            : normalizeArticleText(contentBlocks.join('\n\n'));
          if (text.length < 120) {
            text = normalizeArticleText(clone.innerText || clone.textContent || '');
          }

          const author = authorValue(structuredArticle?.author) ||
            normalizeInline(document.querySelector('meta[name="author"]')?.content ||
              document.querySelector('[rel="author"]')?.textContent) || null;
          const site = normalizeInline(
            structuredArticle?.publisher?.name ||
            document.querySelector('meta[property="og:site_name"]')?.content ||
            location.hostname
          );
          const metadataImage = document.querySelector('meta[property="og:image:secure_url"]')?.content ||
            document.querySelector('meta[property="og:image"]')?.content ||
            document.querySelector('meta[name="twitter:image"]')?.content ||
            document.querySelector('meta[property="twitter:image"]')?.content ||
            document.querySelector('link[rel="image_src"]')?.href || null;
          const image = absoluteURL(imageValue(structuredArticle?.image)) ||
            bestContentImage(root) || absoluteURL(metadataImage);
          return { title, author, site, text, image };
        })();
        """#

        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            throw ReaderError.extractionFailed
        }

        let extractedText = (result["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let captureKind: CaptureKind = extractedText.count >= 120 ? .readableCapture : .referenceOnly
        let text = captureKind == .readableCapture
            ? extractedText
            : "A readable local capture was not available. The source reference is retained."

        return ReaderDocument(
            sourceURL: sourceURL,
            title: (result["title"] as? String)?.nilIfBlank ?? fallbackTitle,
            author: (result["author"] as? String)?.nilIfBlank,
            siteName: (result["site"] as? String)?.nilIfBlank,
            text: text,
            previewImageURL: Self.safeWebURL(result["image"] as? String),
            capturedIdentityID: identityID,
            captureKind: captureKind
        )
    }

    private func updateState() {
        url = webView.url
        title = webView.title?.nilIfBlank ?? webView.url?.host ?? "New Tab"
        canGoBack = webView.canGoBack || sameDocumentHistoryDepth > 0
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        blocksAppPrompts = appPromptPreferences.isBlocked(url: webView.url)
        usesSiteBottomNavigation = siteAccessibilityPreferences.isBottomNavigationEnabled(
            for: webView.url
        )
        refreshLinkOpeningPolicy()
    }

    private func observeWebViewState() {
        let options: NSKeyValueObservingOptions = [.initial, .new]
        webViewObservations = [
            webView.observe(\.url, options: options) { [weak self] _, _ in
                self?.scheduleStateUpdate()
            },
            webView.observe(\.title, options: options) { [weak self] _, _ in
                self?.scheduleStateUpdate()
            },
            webView.observe(\.canGoBack, options: options) { [weak self] _, _ in
                self?.scheduleStateUpdate()
            },
            webView.observe(\.canGoForward, options: options) { [weak self] _, _ in
                self?.scheduleStateUpdate()
            },
            webView.observe(\.isLoading, options: options) { [weak self] _, _ in
                self?.scheduleStateUpdate()
            }
        ]
    }

    nonisolated private func scheduleStateUpdate() {
        Task { @MainActor [weak self] in
            self?.updateState()
        }
    }

    private func handleSameDocumentNavigation(kind: String, fallbackURL: URL? = nil) {
        if kind == "facebookVideoEscape" {
            escapeFacebookVideo(fallbackURL: fallbackURL)
            return
        }

        switch kind {
        case "push":
            sameDocumentHistoryDepth += 1
        case "pop":
            sameDocumentHistoryDepth = max(0, sameDocumentHistoryDepth - 1)
        default:
            break
        }

        url = webView.url
        title = webView.title?.nilIfBlank ?? url?.host ?? "New Tab"
        canGoBack = webView.canGoBack || sameDocumentHistoryDepth > 0
        canGoForward = webView.canGoForward

        if usesSiteBottomNavigation,
           siteAccessibilitySupport?.domainKey == "facebook.com" {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.webView.evaluateJavaScript(
                    Self.enableFacebookBottomNavigationScript
                )
            }
        }
    }

    private func escapeFacebookVideo(fallbackURL: URL?) {
        let startingURL = webView.url
        if webView.canGoBack {
            webView.goBack()
        } else if sameDocumentHistoryDepth > 0 {
            webView.evaluateJavaScript("history.back()")
        } else if let fallbackURL,
                  SiteAccessibilitySupport.resolve(for: fallbackURL)?.domainKey == "facebook.com" {
            load(fallbackURL)
            return
        } else if let currentURL = webView.url,
                  SiteAccessibilitySupport.resolve(for: currentURL)?.domainKey == "facebook.com",
                  let homeURL = URL(string: "/", relativeTo: currentURL)?.absoluteURL {
            load(homeURL)
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self,
                  self.webView.url == startingURL,
                  let destination = fallbackURL,
                  destination != startingURL,
                  SiteAccessibilitySupport.resolve(for: destination)?.domainKey == "facebook.com"
            else { return }
            self.load(destination)
        }
    }

    private static let historyObservationScript = #"""
    (() => {
      if (window.__personalBrowserHistoryObserver) return;
      window.__personalBrowserHistoryObserver = true;

      const report = (kind) => {
        try {
          window.webkit.messageHandlers.browserHistory.postMessage({
            kind
          });
        } catch (_) {}
        window.dispatchEvent(new CustomEvent('personalbrowserhistorychange', {
          detail: { kind }
        }));
      };

      const pushState = history.pushState.bind(history);
      history.pushState = (...args) => {
        const result = pushState(...args);
        report('push');
        return result;
      };

      const replaceState = history.replaceState.bind(history);
      history.replaceState = (...args) => {
        const result = replaceState(...args);
        report('replace');
        return result;
      };

      window.addEventListener('popstate', () => report('pop'));
    })();
    """#

    static let interactionHighlightScript = #"""
    (() => {
      const styleID = 'personalbrowser-interaction-highlight-style';
      const touchFocusClass = 'personalbrowser-touch-focus';
      const setTouchFocus = enabled => {
        const root = document.documentElement;
        if (!root) return false;
        root.classList.toggle(touchFocusClass, enabled);
        return true;
      };
      const install = () => {
        if (document.getElementById(styleID)) return true;
        const parent = document.head || document.documentElement;
        if (!parent) return false;
        const style = document.createElement('style');
        style.id = styleID;
        style.textContent = `
          a, area, button, summary,
          [role="button"], [role="link"], [role="menuitem"],
          input[type="button"], input[type="submit"], input[type="reset"],
          [tabindex]:not(input):not(textarea):not(select) {
            -webkit-tap-highlight-color: rgba(0, 0, 0, 0) !important;
          }

          html.personalbrowser-touch-focus a:focus,
          html.personalbrowser-touch-focus area:focus,
          html.personalbrowser-touch-focus button:focus,
          html.personalbrowser-touch-focus summary:focus,
          html.personalbrowser-touch-focus [role="button"]:focus,
          html.personalbrowser-touch-focus [role="link"]:focus,
          html.personalbrowser-touch-focus [role="menuitem"]:focus,
          html.personalbrowser-touch-focus input[type="button"]:focus,
          html.personalbrowser-touch-focus input[type="submit"]:focus,
          html.personalbrowser-touch-focus input[type="reset"]:focus,
          html.personalbrowser-touch-focus [tabindex]:not(input):not(textarea):not(select):focus {
            outline: none !important;
          }
        `;
        parent.appendChild(style);
        setTouchFocus(matchMedia('(hover: none) and (pointer: coarse)').matches);
        return true;
      };

      document.addEventListener('touchstart', () => setTouchFocus(true), {
        capture: true,
        passive: true
      });
      document.addEventListener('pointerdown', event => {
        if (event.pointerType !== 'mouse') setTouchFocus(true);
      }, true);
      document.addEventListener('keydown', event => {
        if (event.key === 'Tab') setTouchFocus(false);
      }, true);

      if (!install()) {
        new MutationObserver((_, observer) => {
          if (install()) observer.disconnect();
        }).observe(document, { childList: true, subtree: true });
      }
      return true;
    })();
    """#

    private func extractPageVisualMetadata() async -> PageVisualMetadata {
        let script = #"""
        const absoluteURL = (value, baseURL) => {
          if (!value) return null;
          try { return new URL(value, baseURL).href; } catch { return null; }
        };
        const metadataFrom = (doc, baseURL) => {
          const icons = [...doc.querySelectorAll(
            'link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]'
          )];
          const preferredIcon = icons.sort((a, b) => {
            const size = link => parseInt((link.sizes?.value || '0').split('x')[0], 10) || 0;
            return size(b) - size(a);
          })[0]?.getAttribute('href') || null;
          const preview = doc.querySelector('meta[property="og:image:secure_url"]')?.content ||
            doc.querySelector('meta[property="og:image"]')?.content ||
            doc.querySelector('meta[name="twitter:image"]')?.content ||
            doc.querySelector('meta[property="twitter:image"]')?.content ||
            doc.querySelector('link[rel="image_src"]')?.href || null;
          return {
            pageTitle: doc.querySelector('meta[property="og:title"]')?.content || doc.title || null,
            faviconURL: absoluteURL(preferredIcon, baseURL),
            previewImageURL: absoluteURL(preview, baseURL),
            siteName: doc.querySelector('meta[property="og:site_name"]')?.content || null
          };
        };

        const current = metadataFrom(document, document.baseURI);
        let domain = {};
        if (!current.faviconURL || !current.previewImageURL || !current.siteName) {
          try {
            const rootURL = new URL('/', location.origin);
            const response = await fetch(rootURL, { credentials: 'include', cache: 'force-cache' });
            if (response.ok) {
              const rootDocument = new DOMParser().parseFromString(await response.text(), 'text/html');
              domain = metadataFrom(rootDocument, response.url || rootURL.href);
            }
          } catch (_) {}
        }

        return {
          pageTitle: current.pageTitle,
          faviconURL: current.faviconURL || domain.faviconURL ||
            absoluteURL('/favicon.ico', location.origin),
          previewImageURL: current.previewImageURL || domain.previewImageURL || null,
          siteName: current.siteName || domain.siteName || location.hostname
        };
        """#

        let result = try? await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? [String: Any]
        var metadata = PageVisualMetadata(
            pageTitle: (result?["pageTitle"] as? String)?.nilIfBlank,
            siteName: (result?["siteName"] as? String)?.nilIfBlank,
            faviconURL: Self.safeWebURL(result?["faviconURL"] as? String),
            previewImageURL: Self.safeWebURL(result?["previewImageURL"] as? String)
        )
        metadata.snapshotJPEGData = await captureTabSnapshot()
        return metadata
    }

    private func captureTabSnapshot() async -> Data? {
        guard webView.bounds.width > 0, webView.bounds.height > 0 else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds

        let image: UIImage? = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let image else { return nil }

        let targetWidth = min(image.size.width, 480)
        let scale = targetWidth / image.size.width
        let targetSize = CGSize(width: targetWidth, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return thumbnail.jpegData(compressionQuality: 0.68)
    }

    private static func safeWebURL(_ value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    @objc private func handleTwoFingerTap() {
        requestQuickSwitcherIfControlsHidden()
    }

    @discardableResult
    func requestQuickSwitcherIfControlsHidden() -> Bool {
        guard browserControlsPinnedHidden else { return false }
        requestQuickSwitcher()
        return true
    }

    @objc private func handleQuickSwitcherEdgeSwipe(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        guard recognizer.state == .ended,
              QuickSwitcherEdgeSwipePolicy.shouldOpen(
                translation: recognizer.translation(in: webView)
              ) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        requestQuickSwitcher()
    }

    func requestQuickSwitcher() {
        onQuickSwitcherRequested?()
    }

    @objc private func handleContentTap() {
        notifyContentInteraction()
    }

    func notifyContentInteraction() {
        onContentInteraction?()
    }

    private func updateInjectedLinkOpeningPolicy() {
        let value = linkOpeningPolicy.rawValue
        webView.evaluateJavaScript("window.__personalbrowserLinkOpeningPolicy = '\(value)';")
    }

    private func handleDeliberateExternalLink(_ requestedURL: URL) {
        let sourceURL = webView.url
        let destination = SiteWrappedExternalLinkResolver.destination(
            for: requestedURL,
            sourceURL: sourceURL
        )
        guard SiteLinkOpeningPreferences.isExternalLink(from: sourceURL, to: destination) else {
            webView.load(BrowserLanguage.request(for: requestedURL))
            return
        }
        switch linkOpeningPolicy {
        case .followWebsite, .sameTab:
            webView.load(BrowserLanguage.request(for: destination))
        case .newTab:
            rememberRoutedFacebookExternalLink(
                sourceURL: sourceURL,
                requestedURL: requestedURL,
                destinationURL: destination
            )
            onOpenLinkInSelectedTab?(destination)
        case .subtab:
            rememberRoutedFacebookExternalLink(
                sourceURL: sourceURL,
                requestedURL: requestedURL,
                destinationURL: destination
            )
            openSubtab(destination)
        }
    }

    private func rememberRoutedFacebookExternalLink(
        sourceURL: URL?,
        requestedURL: URL,
        destinationURL: URL
    ) {
        guard SiteLinkOpeningPreferences.siteKey(for: sourceURL) == "facebook.com" else { return }
        recentlyRoutedFacebookExternalLink = FacebookExternalLinkRoutingRecord(
            sourceURL: sourceURL,
            requestedURL: requestedURL,
            destinationURL: destinationURL,
            handledAt: Date()
        )
    }

    private func shouldSuppressDuplicateFacebookNavigation(
        requestedURL: URL,
        resolvedURL: URL
    ) -> Bool {
        guard let record = recentlyRoutedFacebookExternalLink else { return false }
        guard Date().timeIntervalSince(record.handledAt) <= 5 else {
            recentlyRoutedFacebookExternalLink = nil
            return false
        }
        guard Self.sameNavigationURL(requestedURL, record.requestedURL)
                || Self.sameNavigationURL(requestedURL, record.destinationURL)
                || Self.sameNavigationURL(resolvedURL, record.destinationURL)
        else { return false }
        recentlyRoutedFacebookExternalLink = nil
        return true
    }

    private static func sameNavigationURL(_ lhs: URL, _ rhs: URL) -> Bool {
        guard var left = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
              var right = URLComponents(url: rhs, resolvingAgainstBaseURL: false) else {
            return lhs == rhs
        }
        left.fragment = nil
        right.fragment = nil
        return left == right
    }

    private func effectiveLinkNavigationType(
        _ navigationType: WKNavigationType,
        sourceURL: URL?,
        destinationURL: URL
    ) -> WKNavigationType {
        guard SiteLinkOpeningPreferences.siteKey(for: sourceURL) == "facebook.com",
              SiteLinkOpeningPreferences.isExternalLink(
                  from: sourceURL,
                  to: destinationURL
              ),
              let activatedAt = lastFacebookUserActivationAt,
              Date().timeIntervalSince(activatedAt) <= 5 else {
            return navigationType
        }
        lastFacebookUserActivationAt = nil
        return .linkActivated
    }

    static let facebookExternalLinkActivationScript = #"""
    (() => {
      window.__personalbrowserLinkOpeningPolicy = window.__personalbrowserLinkOpeningPolicy || 'followWebsite';
      if (window.__personalbrowserFacebookExternalLinkListenerInstalled) return;
      window.__personalbrowserFacebookExternalLinkListenerInstalled = true;

      const isFacebookHost = host => host === 'facebook.com' || host.endsWith('.facebook.com');
      document.addEventListener('click', event => {
        if (window.__personalbrowserLinkOpeningPolicy === 'followWebsite') return;
        if (!isFacebookHost(location.hostname.toLowerCase())) return;
        if (event.defaultPrevented || (typeof event.button === 'number' && event.button !== 0) || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

        try {
          window.webkit.messageHandlers.browserLinkActivation.postMessage({ kind: 'facebookUserActivation' });
        } catch (_) {}

        const path = typeof event.composedPath === 'function' ? event.composedPath() : [event.target];
        const elements = path.filter(node => node instanceof Element);
        const closestAnchor = event.target?.closest?.('a[href]');
        if (closestAnchor && !elements.includes(closestAnchor)) elements.push(closestAnchor);

        let requested = null;
        for (const element of elements) {
          const candidates = [
            element.getAttribute?.('data-lynx-uri'),
            element.getAttribute?.('data-href'),
            element.getAttribute?.('data-url'),
            element.getAttribute?.('href')
          ];
          for (const candidate of candidates) {
            if (!candidate) continue;
            try {
              const parsed = new URL(candidate, document.baseURI);
              if (['http:', 'https:'].includes(parsed.protocol)) {
                requested = parsed;
                break;
              }
            } catch (_) {}
          }
          if (requested) break;
        }
        if (!requested) return;

        let destination = requested;
        const requestedHost = requested.hostname.toLowerCase();
        if ((requestedHost === 'l.facebook.com' || requestedHost === 'lm.facebook.com') && requested.pathname.replace(/\/$/, '') === '/l.php') {
          const wrapped = requested.searchParams.get('u') || requested.searchParams.get('url') || requested.searchParams.get('href');
          if (wrapped) {
            try { destination = new URL(wrapped); } catch (_) {}
          }
        }
        if (isFacebookHost(destination.hostname.toLowerCase())) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        window.webkit.messageHandlers.browserLinkActivation.postMessage({
          kind: 'externalURL',
          url: requested.href
        });
      }, true);
    })();
    """#


    static let enableAppPromptBlockingScript = #"""
    (() => {
      window.__personalbrowserAppPromptBlockingEnabled = true;
      window.__personalbrowserAppPromptObserver?.disconnect();
      if (window.__personalbrowserAppPromptScanTimer) clearTimeout(window.__personalbrowserAppPromptScanTimer);

      const phrases = [
        'get the full app experience',
        'open gmail',
        'get gmail',
        'open in app',
        'open in the app',
        'continue in app',
        'continue in the app',
        'use the app',
        'download the app',
        'get the app',
        'view in app'
      ];
      const flexibleAppPhrase = /\b(?:continue|download|get|install|open|switch|try|use|view)\b.{0,48}\b(?:the\s+)?(?:[\p{L}\p{N}._-]+\s+)?app\b/iu;
      const appExperiencePhrase = /\bapp\b.{0,48}\b(?:experience|version)\b/iu;
      const appTarget = /^(linkedin|instagram|fb|facebook|twitter|x|reddit|youtube|tiktok|pinterest|spotify|googlegmail):|apps\.apple\.com|itunes\.apple\.com|play\.google\.com/i;
      const linkedInHost = /(^|\.)linkedin\.com$/i.test(location.hostname);
      const gmailHost = /(^|\.)(gmail\.com|mail\.google\.com)$/i.test(location.hostname);
      const mutationHeavyHost = linkedInHost || gmailHost;

      const textOf = node => {
        if (!node) return '';
        const parts = [];
        const walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT);
        while (walker.nextNode() && parts.length < 160) {
          const value = (walker.currentNode.nodeValue || '').trim();
          if (value) parts.push(value);
        }
        return parts.join(' ')
          .replace(/\s+/g, ' ')
          .trim()
          .toLowerCase();
      };

      const hasAppPromotionText = node => {
        const text = textOf(node);
        return phrases.some(phrase => text.includes(phrase)) ||
          flexibleAppPhrase.test(text) ||
          appExperiencePhrase.test(text) ||
          (linkedInHost && /\blinkedin\b.{0,48}\bapp\b/i.test(text)) ||
          (gmailHost && /\b(?:gmail|google mail)\b.{0,48}\bapp\b/i.test(text));
      };

      const isAppPrompt = node => {
        if (!(node instanceof HTMLElement) ||
            node.dataset.personalbrowserAppPromptHidden === 'true' ||
            node.dataset.personalbrowserAppPromptDismissPending === 'true') return false;
        const rect = node.getBoundingClientRect();
        if (rect.width < innerWidth * 0.45 || rect.height < 44 || rect.height > innerHeight * 0.92) return false;

        const style = getComputedStyle(node);
        const overlayLike = style.position === 'fixed' ||
          style.position === 'sticky' ||
          node.getAttribute('role') === 'dialog' ||
          node.getAttribute('aria-modal') === 'true';
        if (!overlayLike) return false;

        const text = textOf(node);
        const hasPhrase = hasAppPromotionText(node);
        const hasAppTarget = [...node.querySelectorAll('a[href]')]
          .some(link => appTarget.test(link.href));
        const hasNamedService = (linkedInHost && text.includes('linkedin')) ||
          (gmailHost && (text.includes('gmail') || text.includes('google mail')));
        return hasPhrase && (hasAppTarget || hasNamedService || text.includes('app'));
      };

      const findPromptContainer = seed => {
        for (let node = seed; node && node !== document.body; node = node.parentElement) {
          if (isAppPrompt(node)) return node;
        }
        return null;
      };

      const hideDirectly = target => {
        delete target.dataset.personalbrowserAppPromptDismissPending;
        target.dataset.personalbrowserAppPromptHidden = 'true';
        target.dataset.personalbrowserPreviousDisplay = target.style.display || '';
        target.style.setProperty('display', 'none', 'important');
        window.__personalbrowserAppPromptHiddenCount =
          (window.__personalbrowserAppPromptHiddenCount || 0) + 1;
      };

      const dismissControl = target => [...target.querySelectorAll('button, [role="button"]')]
        .find(control => {
          const labels = [
            control.getAttribute('aria-label') || '',
            control.getAttribute('title') || '',
            textOf(control)
          ].map(label => label.trim()).filter(Boolean);
          return labels.some(label => /^(?:close|dismiss|not now|no thanks|×|✕|✖)$/i.test(label));
        });

      const hideNode = node => {
        let target = node;
        for (let parent = node.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
          const style = getComputedStyle(parent);
          const rect = parent.getBoundingClientRect();
          if (style.position === 'fixed' && rect.width >= innerWidth * 0.8 && rect.height >= innerHeight * 0.35) {
            target = parent;
          }
        }
        const close = dismissControl(target);
        if (close) {
          target.dataset.personalbrowserAppPromptDismissPending = 'true';
          close.click();
          if (target.isConnected && getComputedStyle(target).display !== 'none') {
            hideDirectly(target);
          } else {
            window.__personalbrowserAppPromptHiddenCount =
              (window.__personalbrowserAppPromptHiddenCount || 0) + 1;
          }
          return;
        }
        hideDirectly(target);
      };

      const overlaySelector = [
        '[role="dialog"]', '[aria-modal="true"]',
        '[class*="modal"]', '[class*="overlay"]',
        '[class*="bottom-sheet"]', '[class*="bottomsheet"]',
        '[class*="upsell"]', '[class*="app-promo"]'
      ].join(',');
      const controlSelector = 'a[href], button, [role="button"], [role="link"]';
      const elementsMatching = (root, selector) => {
        const matches = [];
        if (root instanceof Element && root.matches(selector)) matches.push(root);
        if (typeof root.querySelectorAll === 'function') matches.push(...root.querySelectorAll(selector));
        return matches;
      };

      const scan = root => {
        if (!window.__personalbrowserAppPromptBlockingEnabled) return;
        if (root === document) {
          window.__personalbrowserAppPromptFullDocumentScans =
            (window.__personalbrowserAppPromptFullDocumentScans || 0) + 1;
        }
        const candidates = new Set(elementsMatching(root, overlaySelector));
        elementsMatching(root, controlSelector)
          .forEach(control => {
            let node = control;
            for (let depth = 0; node && node !== document.body && depth < 7; depth += 1, node = node.parentElement) {
              const text = textOf(node);
              if (text.length > 700) break;
              if (hasAppPromotionText(node)) {
                candidates.add(node);
                return;
              }
            }
            const label = `${control.getAttribute('aria-label') || ''} ${control.getAttribute('title') || ''}`;
            if (/\b(app|continue|open|use)\b/i.test(label)) candidates.add(control);
          });
        candidates.forEach(seed => {
          const prompt = findPromptContainer(seed);
          if (prompt) hideNode(prompt);
        });
      };

      const pendingRoots = new Set();
      const isBoundedMutationRoot = node => {
        if (!(node instanceof Element)) return false;
        if (!mutationHeavyHost) return true;
        if (node.matches(overlaySelector)) return true;
        const parent = node.parentElement;
        if (parent !== document.body && parent !== document.documentElement) return false;
        if (node.querySelector(overlaySelector)) return true;
        const text = textOf(node);
        return text.length <= 1200 && hasAppPromotionText(node);
      };
      const scheduleScan = records => {
        records.forEach(record => record.addedNodes.forEach(node => {
          if (isBoundedMutationRoot(node) && pendingRoots.size < 12) pendingRoots.add(node);
        }));
        if (window.__personalbrowserAppPromptScanTimer) return;
        window.__personalbrowserAppPromptScanTimer = setTimeout(() => {
          window.__personalbrowserAppPromptScanTimer = null;
          const roots = [...pendingRoots];
          pendingRoots.clear();
          roots.forEach(root => {
            if (root.isConnected) scan(root);
          });
        }, mutationHeavyHost ? 300 : 100);
      };

      window.__personalbrowserAppPromptObserver = new MutationObserver(scheduleScan);
      window.__personalbrowserAppPromptObserver.observe(document.documentElement, { childList: true, subtree: true });
      scan(document);
      return true;
    })();
    """#

    private static let disableAppPromptBlockingScript = #"""
    (() => {
      window.__personalbrowserAppPromptBlockingEnabled = false;
      window.__personalbrowserAppPromptObserver?.disconnect();
      window.__personalbrowserAppPromptObserver = null;
      if (window.__personalbrowserAppPromptScanTimer) clearTimeout(window.__personalbrowserAppPromptScanTimer);
      window.__personalbrowserAppPromptScanTimer = null;
      document.querySelectorAll('[data-personalbrowser-app-prompt-hidden="true"]').forEach(node => {
        node.style.display = node.dataset.personalbrowserPreviousDisplay || '';
        delete node.dataset.personalbrowserAppPromptHidden;
        delete node.dataset.personalbrowserPreviousDisplay;
      });
      document.querySelectorAll('[data-personalbrowser-app-prompt-dismiss-pending="true"]').forEach(node => {
        delete node.dataset.personalbrowserAppPromptDismissPending;
      });
      return true;
    })();
    """#

    static let enableFacebookBottomNavigationScript = #"""
    (() => {
      const isFacebookHost = value => {
        const host = String(value || '').toLowerCase();
        return host === 'facebook.com' || host.endsWith('.facebook.com');
      };
      if (!isFacebookHost(location.hostname)) {
        return { status: 'unsupported' };
      }

      window.__personalbrowserFacebookBottomNavigationEnabled = true;
      if (window.__personalbrowserFacebookBottomNavigationTimer) {
        clearTimeout(window.__personalbrowserFacebookBottomNavigationTimer);
        window.__personalbrowserFacebookBottomNavigationTimer = null;
      }

      const footerID = 'personalbrowser-facebook-accessibility-footer';
      const styleID = 'personalbrowser-facebook-bottom-navigation-style';
      const spacerID = 'personalbrowser-facebook-bottom-navigation-spacer';
      const videoEscapeID = 'personalbrowser-facebook-video-escape';
      const sectionKey = url => (url.searchParams.get('sk') || '').toLowerCase();
      const slots = [
        {
          key: 'home', label: 'Home', fallback: '/',
          matches: url => /^\/home(?:\.php|\/|$)/.test(url.pathname) ||
            (url.pathname === '/' && ['', 'h_chr', 'home', 'feed'].includes(sectionKey(url))),
          icon: '<path d="M3 10.8 12 3l9 7.8v9.7a.5.5 0 0 1-.5.5H15v-6H9v6H3.5a.5.5 0 0 1-.5-.5z"/>'
        },
        {
          key: 'friends', label: 'Friends', fallback: '/friends/',
          matches: url => /^\/(friends|people)(?:\.php|\/|$)/.test(url.pathname) ||
            ['friends', 'people'].includes(sectionKey(url)),
          icon: '<path d="M8.2 11.2a3.6 3.6 0 1 0 0-7.2 3.6 3.6 0 0 0 0 7.2Zm7-1.2a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM2 20c.2-4.1 2.3-6.2 6.2-6.2s6 2.1 6.2 6.2H2Zm12.2-6.7c4.2.1 6.5 2.3 6.8 6.7h-4.8a9.2 9.2 0 0 0-2-6.7Z"/>'
        },
        {
          key: 'video', label: 'Video', fallback: '/watch/',
          matches: url => /^\/(watch|video|reel)(?:\/|$)/.test(url.pathname) ||
            ['watch', 'video', 'videos'].includes(sectionKey(url)),
          icon: '<path d="M3.5 5h17v14h-17zM9 9v6l6-3zM7 2l2 3m5-3-2 3"/>'
        },
        {
          key: 'marketplace', label: 'Marketplace', fallback: '/marketplace/',
          matches: url => /^\/marketplace(?:\/|$)/.test(url.pathname) ||
            sectionKey(url) === 'marketplace',
          icon: '<path d="M3 8h18l-2-5H5L3 8Zm1 2v10h16V10M8 20v-6h8v6"/>'
        },
        {
          key: 'notifications', label: 'Notifications', fallback: '/notifications.php',
          matches: url => /^\/notifications(?:\.php|\/|$)/.test(url.pathname) ||
            sectionKey(url) === 'notifications',
          icon: '<path d="M6 10a6 6 0 0 1 12 0v4l2 3H4l2-3v-4Zm4 10h4"/>'
        },
        {
          key: 'menu', label: 'Menu', fallback: '/?sk=bookmarks',
          matches: url => /^\/(menu|bookmarks)(?:\/|$)/.test(url.pathname) ||
            ['menu', 'bookmarks'].includes(sectionKey(url)),
          controlLabels: [
            'menu', 'open menu', 'main menu', 'navigation menu',
            'valikko', 'avaa valikko', 'meny', 'oppna menyn',
            'menü', 'menú'
          ],
          icon: '<path d="M4 6h16M4 12h16M4 18h16"/>'
        }
      ];

      const parsedURL = anchor => {
        try {
          const url = new URL(anchor.getAttribute('href'), location.href);
          return isFacebookHost(url.hostname) ? url : null;
        } catch (_) {
          return null;
        }
      };

      const labelFor = (element, slot) => {
        const text = element?.getAttribute('aria-label') ||
          element?.getAttribute('title') || element?.textContent || slot.label;
        const normalized = text.replace(/\s+/g, ' ').trim();
        return normalized && normalized.length <= 32 ? normalized : slot.label;
      };

      const scoreElement = element => {
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        if (style.display === 'none' || style.visibility === 'hidden') return -Infinity;
        let score = 0;
        if (element.getAttribute('role') === 'tab') score += 120;
        if (element.closest('nav, [role="navigation"], [role="tablist"], header')) score += 90;
        if (element.querySelector('svg, img')) score += 45;
        if (element.getAttribute('aria-label') || element.getAttribute('title')) score += 30;
        if (rect.width >= 36 && rect.height >= 36) score += 25;
        score += Math.max(0, 80 - Math.abs(rect.top));
        return score;
      };

      const normalizedControlLabel = element => String(
        element.getAttribute('aria-label') ||
        element.getAttribute('title') ||
        element.textContent || ''
      ).replace(/\s+/g, ' ').trim().toLocaleLowerCase();

      const findActionControl = slot => {
        if (!slot.controlLabels) return null;
        const controls = new Set();
        document.querySelectorAll('button, [role="button"], [aria-label], [title]').forEach(node => {
          const control = node.closest('button, [role="button"]');
          if (control && !control.closest(`#${footerID}`)) controls.add(control);
        });
        return [...controls]
          .map(element => ({
            element,
            url: null,
            label: normalizedControlLabel(element),
            score: scoreElement(element)
          }))
          .filter(candidate => candidate.label && slot.controlLabels.some(label =>
            candidate.label === label || candidate.label.startsWith(`${label},`) ||
              candidate.label.startsWith(`${label} `)
          ))
          .filter(candidate => Number.isFinite(candidate.score))
          .sort((left, right) => right.score - left.score)[0] || null;
      };

      const findSource = slot => {
        const anchorSource = [...document.querySelectorAll('a[href]')]
          .filter(anchor => !anchor.closest(`#${footerID}`))
          .map(anchor => ({ element: anchor, url: parsedURL(anchor) }))
          .filter(candidate => candidate.url && slot.matches(candidate.url))
          .map(candidate => ({ ...candidate, score: scoreElement(candidate.element) }))
          .filter(candidate => Number.isFinite(candidate.score))
          .sort((left, right) => right.score - left.score)[0] || null;
        const actionSource = findActionControl(slot);
        return actionSource || anchorSource;
      };

      const fallbackIcon = slot => `
        <svg viewBox="0 0 24 24" aria-hidden="true" fill="none"
             stroke="currentColor" stroke-width="2" stroke-linecap="round"
             stroke-linejoin="round">${slot.icon}</svg>`;

      const sourceIcon = (_, slot) => fallbackIcon(slot);

      const ensureStyle = () => {
        if (document.getElementById(styleID)) return;
        const style = document.createElement('style');
        style.id = styleID;
        style.textContent = `
          #${footerID} {
            position: fixed !important;
            inset: auto 0 0 0 !important;
            z-index: 2147483000 !important;
            display: grid !important;
            grid-template-columns: repeat(var(--personalbrowser-facebook-items), minmax(0, 1fr)) !important;
            min-height: 58px !important;
            background: var(--surface-background, var(--card-background, #fff)) !important;
            padding-bottom: env(safe-area-inset-bottom) !important;
            box-sizing: border-box !important;
            box-shadow: 0 -1px 0 rgba(0, 0, 0, 0.12) !important;
            font-family: system-ui, -apple-system, BlinkMacSystemFont, sans-serif !important;
          }
          #${footerID} button {
            appearance: none !important;
            border: 0 !important;
            margin: 0 !important;
            padding: 7px 2px 5px !important;
            min-width: 0 !important;
            min-height: 52px !important;
            background: transparent !important;
            color: var(--secondary-icon, #65676b) !important;
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
            justify-content: center !important;
            gap: 2px !important;
            font: inherit !important;
            -webkit-tap-highlight-color: transparent !important;
          }
          #${footerID} button[aria-current="page"] {
            color: var(--blue-link, #0866ff) !important;
          }
          #${footerID} svg,
          #${footerID} img {
            width: 24px !important;
            height: 24px !important;
            max-width: 24px !important;
            max-height: 24px !important;
            object-fit: contain !important;
            color: inherit !important;
            fill: currentColor !important;
          }
          #${footerID} .personalbrowser-facebook-footer-label {
            max-width: 100% !important;
            overflow: hidden !important;
            text-overflow: ellipsis !important;
            white-space: nowrap !important;
            font-size: 10px !important;
            font-weight: 600 !important;
            line-height: 12px !important;
          }
          #${videoEscapeID} {
            appearance: none !important;
            position: fixed !important;
            top: max(12px, env(safe-area-inset-top)) !important;
            left: 12px !important;
            z-index: 2147483646 !important;
            width: 44px !important;
            height: 44px !important;
            margin: 0 !important;
            padding: 0 !important;
            border: 1px solid rgba(255, 255, 255, 0.24) !important;
            border-radius: 22px !important;
            background: rgba(20, 20, 20, 0.72) !important;
            color: #fff !important;
            box-shadow: 0 4px 18px rgba(0, 0, 0, 0.28) !important;
            display: flex !important;
            align-items: center !important;
            justify-content: center !important;
            -webkit-backdrop-filter: blur(14px) saturate(1.15) !important;
            backdrop-filter: blur(14px) saturate(1.15) !important;
            -webkit-tap-highlight-color: transparent !important;
          }
          #${videoEscapeID} svg {
            width: 24px !important;
            height: 24px !important;
            fill: none !important;
            stroke: currentColor !important;
            stroke-width: 2.4 !important;
            stroke-linecap: round !important;
            stroke-linejoin: round !important;
          }
        `;
        (document.head || document.documentElement).appendChild(style);
      };

      const ensureSpacer = () => {
        let spacer = document.getElementById(spacerID);
        if (!spacer) {
          spacer = document.createElement('div');
          spacer.id = spacerID;
          spacer.setAttribute('aria-hidden', 'true');
          spacer.style.pointerEvents = 'none';
          document.body?.appendChild(spacer);
        }
        if (spacer) spacer.style.height = '64px';
      };

      const isSelected = (slot, source) => {
        if (source?.element &&
            (source.element.getAttribute('aria-current') === 'page' ||
             source.element.getAttribute('aria-selected') === 'true' ||
             source.element.closest('[aria-current="page"], [aria-selected="true"]'))) {
          return true;
        }
        try { return slot.matches(new URL(location.href)); }
        catch (_) { return false; }
      };

      const isVisible = element => {
        if (!element?.isConnected) return false;
        const style = getComputedStyle(element);
        if (style.display === 'none' || style.visibility === 'hidden' ||
            Number.parseFloat(style.opacity || '1') <= 0.01) return false;
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 && rect.bottom > 0 &&
          rect.right > 0 && rect.top < innerHeight && rect.left < innerWidth;
      };

      const isImmersiveVideoMode = () => {
        let current;
        try { current = new URL(location.href); }
        catch (_) { return false; }
        const path = current.pathname.toLowerCase();
        if (/^\/(reel|reels)(?:\/|$)/.test(path)) return true;
        if (/^\/watch(?:\/|$)/.test(path) &&
            (current.searchParams.has('v') || /^\/watch\/[^/]+/.test(path))) return true;
        if (/\/videos?\/[^/]+/.test(path)) return true;

        return [...document.querySelectorAll('video')].slice(0, 24).some(video => {
          if (!isVisible(video)) return false;
          const rect = video.getBoundingClientRect();
          const modal = video.closest('[role="dialog"], [aria-modal="true"]');
          if (modal && isVisible(modal)) return true;
          const viewportCoverage = rect.width >= innerWidth * 0.72 &&
            rect.height >= innerHeight * 0.62;
          if (!viewportCoverage) return false;
          let ancestor = video;
          for (let depth = 0; ancestor && depth < 5; depth += 1, ancestor = ancestor.parentElement) {
            const position = getComputedStyle(ancestor).position;
            if (position === 'fixed') return true;
          }
          return false;
        });
      };

      const nativeVideoExitControl = () => {
        const labels = new Set([
          'back', 'go back', 'close', 'close video', 'exit', 'done',
          'takaisin', 'sulje', 'stang', 'stäng', 'tillbaka',
          'zuruck', 'zurück', 'schliessen', 'schließen',
          'cerrar', 'volver', 'fermer', 'retour', 'chiudi', 'indietro'
        ]);
        const candidates = [...document.querySelectorAll(
          '[role="dialog"] button, [role="dialog"] [role="button"], ' +
          '[aria-modal="true"] button, [aria-modal="true"] [role="button"], ' +
          'button[aria-label], [role="button"][aria-label], a[aria-label]'
        )];
        return candidates
          .filter(element => !element.closest(
            `#${footerID}, #${videoEscapeID}`
          ))
          .filter(isVisible)
          .map(element => {
            const label = normalizedControlLabel(element);
            const rect = element.getBoundingClientRect();
            const exactLabel = labels.has(label) || [...labels].some(value =>
              label.startsWith(`${value},`) || label.startsWith(`${value} `)
            );
            const score = (exactLabel ? 200 : 0) +
              (element.closest('[role="dialog"], [aria-modal="true"]') ? 80 : 0) +
              (rect.top < 180 ? 40 : 0) +
              (rect.width >= 32 && rect.height >= 32 ? 20 : 0);
            return { element, exactLabel, score };
          })
          .filter(candidate => candidate.exactLabel)
          .sort((left, right) => right.score - left.score)[0]?.element || null;
      };

      const removeVideoEscape = () => {
        document.getElementById(videoEscapeID)?.remove();
        window.__personalbrowserFacebookVideoEscapeActive = false;
      };

      const ensureVideoEscape = () => {
        const immersive = isImmersiveVideoMode();
        if (!immersive) {
          window.__personalbrowserFacebookLastNonVideoURL = location.href;
          window.__personalbrowserFacebookVideoEntryURL = null;
          removeVideoEscape();
          return;
        }

        if (!window.__personalbrowserFacebookVideoEscapeActive) {
          window.__personalbrowserFacebookVideoEntryURL =
            window.__personalbrowserFacebookLastNonVideoURL || null;
        }
        window.__personalbrowserFacebookVideoEscapeActive = true;
        let button = document.getElementById(videoEscapeID);
        if (button) return;

        button = document.createElement('button');
        button.id = videoEscapeID;
        button.type = 'button';
        button.setAttribute('aria-label', 'Back from video');
        button.setAttribute('data-personalbrowser-accessibility-control', 'true');
        button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5l-7 7 7 7"/></svg>';
        button.addEventListener('click', event => {
          event.preventDefault();
          event.stopPropagation();
          const nativeControl = nativeVideoExitControl();
          if (nativeControl) {
            nativeControl.click();
            scheduleBuild();
            return;
          }

          const entryURL = window.__personalbrowserFacebookVideoEntryURL;
          try {
            window.webkit.messageHandlers.browserHistory.postMessage({
              kind: 'facebookVideoEscape',
              fallbackURL: entryURL || new URL('/', location.origin).href
            });
          } catch (_) {
            if (history.length > 1) {
              history.back();
            } else {
              location.assign(entryURL || new URL('/', location.origin).href);
            }
          }
        });
        document.body?.appendChild(button);
      };

      const build = () => {
        if (!window.__personalbrowserFacebookBottomNavigationEnabled) return false;
        ensureStyle();
        ensureVideoEscape();
        document.getElementById(footerID)?.remove();
        ensureSpacer();
        return true;
      };

      const scheduleBuild = (attempt = 0) => {
        if (!window.__personalbrowserFacebookBottomNavigationEnabled ||
            window.__personalbrowserFacebookBottomNavigationTimer) return;
        window.__personalbrowserFacebookBottomNavigationTimer = setTimeout(() => {
          window.__personalbrowserFacebookBottomNavigationTimer = null;
          if (!build() && attempt < 10) scheduleBuild(attempt + 1);
        }, attempt === 0 ? 80 : 350);
      };

      if (window.__personalbrowserFacebookBottomNavigationRefresh) {
        window.removeEventListener(
          'personalbrowserhistorychange',
          window.__personalbrowserFacebookBottomNavigationRefresh
        );
        window.removeEventListener('popstate', window.__personalbrowserFacebookBottomNavigationRefresh);
        window.removeEventListener('hashchange', window.__personalbrowserFacebookBottomNavigationRefresh);
      }
      window.__personalbrowserFacebookBottomNavigationRefresh = () => scheduleBuild();
      window.addEventListener(
        'personalbrowserhistorychange',
        window.__personalbrowserFacebookBottomNavigationRefresh
      );
      window.addEventListener('popstate', window.__personalbrowserFacebookBottomNavigationRefresh);
      window.addEventListener('hashchange', window.__personalbrowserFacebookBottomNavigationRefresh);
      if (window.__personalbrowserFacebookBottomNavigationClickRefresh) {
        document.removeEventListener(
          'click',
          window.__personalbrowserFacebookBottomNavigationClickRefresh,
          true
        );
      }
      window.__personalbrowserFacebookBottomNavigationClickRefresh = event => {
        if (event.target?.closest?.(`#${footerID}, #${videoEscapeID}`)) return;
        scheduleBuild();
        setTimeout(() => scheduleBuild(), 300);
      };
      document.addEventListener(
        'click',
        window.__personalbrowserFacebookBottomNavigationClickRefresh,
        true
      );

      const applied = build();
      if (!applied) scheduleBuild(1);
      return { status: applied ? 'applied' : 'waiting' };
    })();
    """#

    static let disableFacebookBottomNavigationScript = #"""
    (() => {
      window.__personalbrowserFacebookBottomNavigationEnabled = false;
      if (window.__personalbrowserFacebookBottomNavigationTimer) {
        clearTimeout(window.__personalbrowserFacebookBottomNavigationTimer);
        window.__personalbrowserFacebookBottomNavigationTimer = null;
      }
      if (window.__personalbrowserFacebookBottomNavigationRefresh) {
        window.removeEventListener(
          'personalbrowserhistorychange',
          window.__personalbrowserFacebookBottomNavigationRefresh
        );
        window.removeEventListener('popstate', window.__personalbrowserFacebookBottomNavigationRefresh);
        window.removeEventListener('hashchange', window.__personalbrowserFacebookBottomNavigationRefresh);
        window.__personalbrowserFacebookBottomNavigationRefresh = null;
      }
      if (window.__personalbrowserFacebookBottomNavigationClickRefresh) {
        document.removeEventListener(
          'click',
          window.__personalbrowserFacebookBottomNavigationClickRefresh,
          true
        );
        window.__personalbrowserFacebookBottomNavigationClickRefresh = null;
      }
      document.getElementById('personalbrowser-facebook-accessibility-footer')?.remove();
      document.getElementById('personalbrowser-facebook-bottom-navigation-style')?.remove();
      document.getElementById('personalbrowser-facebook-bottom-navigation-spacer')?.remove();
      document.getElementById('personalbrowser-facebook-video-escape')?.remove();
      window.__personalbrowserFacebookVideoEscapeActive = false;
      window.__personalbrowserFacebookVideoEntryURL = null;
      return { status: 'restored' };
    })();
    """#
}

extension WebPage: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === quickSwitcherEdgeGesture,
              let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        return QuickSwitcherEdgeSwipePolicy.canBegin(
            controlsHidden: browserControlsPinnedHidden,
            velocity: panGesture.velocity(in: webView)
        )
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer !== quickSwitcherEdgeGesture
            && otherGestureRecognizer !== quickSwitcherEdgeGesture
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === quickSwitcherEdgeGesture
    }
}

private final class BrowserHistoryScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let messageName = "browserHistory"
    var onMessage: ((String, URL?) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else { return }
        let fallbackURL = (body["fallbackURL"] as? String).flatMap(URL.init(string:))
        onMessage?(kind, fallbackURL)
    }
}

private final class BrowserLinkActivationScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let messageName = "browserLinkActivation"
    var onActivation: ((URL?) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName,
              message.frameInfo.isMainFrame,
              Self.isFacebookHost(message.frameInfo.securityOrigin.host),
              Self.isFacebookHost(message.webView?.url?.host) else { return }

        if let value = message.body as? String,
           let url = URL(string: value),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            onActivation?(url)
            return
        }

        guard let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else { return }
        if kind == "facebookUserActivation" {
            onActivation?(nil)
            return
        }
        guard kind == "externalURL",
              let value = body["url"] as? String,
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        onActivation?(url)
    }

    private static func isFacebookHost(_ rawHost: String?) -> Bool {
        guard let host = rawHost?.lowercased(), !host.isEmpty else { return false }
        return host == "facebook.com" || host.hasSuffix(".facebook.com")
    }
}

enum FacebookAccessibilityDestination: String, CaseIterable, Identifiable {
    case home
    case friends
    case video
    case marketplace
    case notifications
    case menu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .friends: "Friends"
        case .video: "Video"
        case .marketplace: "Marketplace"
        case .notifications: "Notifications"
        case .menu: "Menu"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .friends: "person.2.fill"
        case .video: "play.rectangle.fill"
        case .marketplace: "storefront.fill"
        case .notifications: "bell.fill"
        case .menu: "line.3.horizontal"
        }
    }

    var url: URL {
        switch self {
        case .home: URL(string: "https://www.facebook.com/")!
        case .friends: URL(string: "https://www.facebook.com/friends/")!
        case .video: URL(string: "https://www.facebook.com/watch/")!
        case .marketplace: URL(string: "https://www.facebook.com/marketplace/")!
        case .notifications: URL(string: "https://www.facebook.com/notifications.php")!
        case .menu: URL(string: "https://www.facebook.com/?sk=bookmarks")!
        }
    }

    func matches(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        let section = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "sk" })?.value?.lowercased()
        switch self {
        case .home:
            return path == "/" && !["bookmarks", "friends", "marketplace", "notifications"].contains(section)
        case .friends: return path.hasPrefix("/friends") || section == "friends"
        case .video: return path.hasPrefix("/watch") || path.hasPrefix("/reel") || section == "watch"
        case .marketplace: return path.hasPrefix("/marketplace") || section == "marketplace"
        case .notifications: return path.hasPrefix("/notifications") || section == "notifications"
        case .menu: return path.hasPrefix("/bookmarks") || section == "bookmarks"
        }
    }
}

enum FacebookAccessibilityNavigation {
    static func destination(for key: String) -> URL? {
        FacebookAccessibilityDestination(rawValue: key.lowercased())?.url
    }
}

extension WebPage: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        guard let linkURL = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }

        let isWebLink = ["http", "https"].contains(linkURL.scheme?.lowercased() ?? "")
        let configuration = UIContextMenuConfiguration(
            identifier: linkURL.absoluteString as NSString,
            previewProvider: nil
        ) { [weak self, weak webView] _ in
            var actions: [UIMenuElement] = []

            if isWebLink {
                actions.append(
                    UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                        self?.onOpenLinkInNewTab?(linkURL)
                    }
                )
                actions.append(
                    UIAction(title: "Open in Incognito", image: UIImage(systemName: "eye.slash")) { _ in
                        self?.onOpenLinkInIncognito?(linkURL)
                    }
                )
                actions.append(
                    UIAction(title: "Add to Library", image: UIImage(systemName: "text.badge.plus")) { _ in
                        self?.onAddLinkToReadingList?(linkURL)
                    }
                )
            }

            actions.append(
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.url = linkURL
                }
            )
            actions.append(
                UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    guard let webView else { return }
                    Self.presentShareSheet(for: linkURL, from: webView)
                }
            )

            return UIMenu(children: actions)
        }
        completionHandler(configuration)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let requestedURL = navigationAction.request.url {
            let url = SiteWrappedExternalLinkResolver.destination(
                for: requestedURL,
                sourceURL: webView.url
            )
            if shouldSuppressDuplicateFacebookNavigation(
                requestedURL: requestedURL,
                resolvedURL: url
            ) {
                return nil
            }
            let decision = BrowserNavigationDestinationPolicy.decision(
               for: url,
               currentURL: webView.url,
               navigationType: navigationAction.navigationType
            )
            if decision == .handleExternalApp {
                _ = handleExternalAppLink(url)
            } else if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                let effectiveNavigationType = effectiveLinkNavigationType(
                    navigationAction.navigationType,
                    sourceURL: webView.url,
                    destinationURL: url
                )
                switch BrowserLinkRoutingPolicy.action(
                    for: linkOpeningPolicy,
                    sourceURL: webView.url,
                    destinationURL: url,
                    navigationType: effectiveNavigationType,
                    isSameDocument: BrowserLinkRoutingPolicy.isSameDocument(
                        url,
                        currentURL: webView.url
                    ),
                    shouldDownload: navigationAction.shouldPerformDownload
                ) {
                case .loadInSameTab:
                    if url == requestedURL {
                        webView.load(navigationAction.request)
                    } else {
                        webView.load(BrowserLanguage.request(for: url))
                    }
                case .openNewTab:
                    rememberRoutedFacebookExternalLink(
                        sourceURL: webView.url,
                        requestedURL: requestedURL,
                        destinationURL: url
                    )
                    onOpenLinkInSelectedTab?(url)
                case .openSubtab:
                    rememberRoutedFacebookExternalLink(
                        sourceURL: webView.url,
                        requestedURL: requestedURL,
                        destinationURL: url
                    )
                    openSubtab(url)
                case .followWebsite:
                    onOpenNewTab?(url)
                }
            }
        }
        return nil
    }
}

private extension WebPage {
    static func presentShareSheet(for url: URL, from sourceView: UIView) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = sourceView
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: sourceView.bounds.midX,
            y: sourceView.bounds.midY,
            width: 1,
            height: 1
        )

        var presenter = sourceView.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        presenter?.present(controller, animated: true)
    }
}

extension WebPage: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        if let destinationURL = navigationAction.request.url,
           destinationURL == allowedExternalWebURLOnce {
            allowedExternalWebURLOnce = nil
            return navigationAction.shouldPerformDownload ? .download : .allow
        }
        let destinationDecision = BrowserNavigationDestinationPolicy.decision(
            for: navigationAction.request.url,
            currentURL: webView.url,
            navigationType: navigationAction.navigationType
        )
        if destinationDecision == .handleExternalApp {
            if let url = navigationAction.request.url {
                _ = handleExternalAppLink(url)
            }
            return .cancel
        }
        if navigationAction.shouldPerformDownload {
            return .download
        }
        if let requestedURL = navigationAction.request.url,
           ["http", "https"].contains(requestedURL.scheme?.lowercased() ?? "") {
            let url = SiteWrappedExternalLinkResolver.destination(
                for: requestedURL,
                sourceURL: webView.url
            )
            if shouldSuppressDuplicateFacebookNavigation(
                requestedURL: requestedURL,
                resolvedURL: url
            ) {
                return .cancel
            }
            let effectiveNavigationType = effectiveLinkNavigationType(
                navigationAction.navigationType,
                sourceURL: webView.url,
                destinationURL: url
            )
            switch BrowserLinkRoutingPolicy.action(
                for: linkOpeningPolicy,
                sourceURL: webView.url,
                destinationURL: url,
                navigationType: effectiveNavigationType,
                isSameDocument: BrowserLinkRoutingPolicy.isSameDocument(
                    url,
                    currentURL: webView.url
                ),
                shouldDownload: navigationAction.shouldPerformDownload
            ) {
            case .openNewTab:
                rememberRoutedFacebookExternalLink(
                    sourceURL: webView.url,
                    requestedURL: requestedURL,
                    destinationURL: url
                )
                onOpenLinkInSelectedTab?(url)
                return .cancel
            case .openSubtab:
                rememberRoutedFacebookExternalLink(
                    sourceURL: webView.url,
                    requestedURL: requestedURL,
                    destinationURL: url
                )
                openSubtab(url)
                return .cancel
            case .followWebsite, .loadInSameTab:
                if url != requestedURL {
                    webView.load(BrowserLanguage.request(for: url))
                    return .cancel
                }
            }
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        if Self.responseRequestsDownload(navigationResponse.response) {
            return .download
        }
        return navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        register(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        register(download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        sameDocumentHistoryDepth = 0
        chromeBars.show(animated: false)
        errorMessage = nil
        updateState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState()
        refreshLinkOpeningPolicy()
        if blocksAppPrompts {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.webView.evaluateJavaScript(Self.enableAppPromptBlockingScript)
            }
        }
        if usesSiteBottomNavigation,
           siteAccessibilitySupport?.domainKey == "facebook.com" {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.webView.evaluateJavaScript(
                    Self.enableFacebookBottomNavigationScript
                )
            }
        }
        Task { [weak self] in
            guard let self, let url = webView.url else { return }
            let metadata = await self.extractPageVisualMetadata()
            self.latestPageMetadata = metadata
            self.onNavigationCommitted?(url, metadata.pageTitle ?? self.title, metadata)
        }
        Task { [weak self] in
            await self?.detectSignInForm()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationFailure(error)
    }
}

private extension WebPage {
    static func responseRequestsDownload(_ response: URLResponse) -> Bool {
        guard let response = response as? HTTPURLResponse,
              let disposition = response.value(forHTTPHeaderField: "Content-Disposition") else {
            return false
        }
        return disposition.range(of: "attachment", options: .caseInsensitive) != nil
    }

    func handleNavigationFailure(_ error: Error) {
        updateState()
        let error = error as NSError
        if BrowserDownloadInterruption.matches(error) || error.code == NSURLErrorCancelled {
            errorMessage = nil
            return
        }
        errorMessage = error.localizedDescription
    }

    func showDownloadNotice(_ message: String, systemImage: String, isFailure: Bool = false) {
        downloadNoticeTask?.cancel()
        let notice = BrowserDownloadNotice(
            message: message,
            systemImage: systemImage,
            isFailure: isFailure
        )
        downloadNotice = notice
        downloadNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled, self?.downloadNotice?.id == notice.id else { return }
            self?.downloadNotice = nil
        }
    }

    func detectSignInForm() async {
        guard !isPrivateSession,
              let url = webView.url,
              let host = AppPromptPreferences.normalizedHost(from: url),
              !dismissedSignInHosts.contains(host),
              !sessionRetentionPreferences.keepsSession(url: url) else {
            return
        }

        let script = #"""
        (() => Boolean(document.querySelector(
          'input[type="password"], input[autocomplete="current-password"], input[autocomplete="new-password"]'
        )))()
        """#
        guard let hasPasswordField = try? await webView.evaluateJavaScript(script) as? Bool,
              hasPasswordField else { return }
        signInOfferHost = host
    }

    func register(_ download: WKDownload, id: UUID = UUID()) {
        activeDownloads[id] = download
        downloadIDs[ObjectIdentifier(download)] = id
        download.delegate = self
        downloadObservations[id] = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                self?.onDownloadProgress?(id, progress.fractionCompleted)
            }
        }
    }

    func cleanupDownload(_ id: UUID) {
        if let download = activeDownloads.removeValue(forKey: id) {
            downloadIDs.removeValue(forKey: ObjectIdentifier(download))
        }
        downloadObservations[id]?.invalidate()
        downloadObservations[id] = nil
        downloadFilenames[id] = nil
        resumedRetryIDs.remove(id)
        retryDownloadRecords[id] = nil
    }
}

extension WebPage: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        guard let id = downloadIDs[ObjectIdentifier(download)] else {
            completionHandler(nil)
            return
        }

        let sourceURL = download.originalRequest?.url ?? response.url ?? webView.url
        guard let sourceURL else {
            cleanupDownload(id)
            completionHandler(nil)
            onDownloadFailed?(id, "The download source was unavailable.", false, nil)
            return
        }

        do {
            let destination = try BrowserDownloadSupport.uniqueDestinationURL(
                suggestedFilename: suggestedFilename,
                sourceURL: sourceURL,
                directory: downloadDirectory
            )
            downloadFilenames[id] = destination.lastPathComponent
            let priorRecord = retryDownloadRecords[id]
            let contentType = BrowserDownloadSupport.contentType(
                mimeType: response.mimeType,
                filename: destination.lastPathComponent
            )
            onDownloadStarted?(
                BrowserDownloadRecord(
                    id: id,
                    sourceURL: sourceURL,
                    fileName: destination.lastPathComponent,
                    localFilename: destination.lastPathComponent,
                    identityID: priorRecord?.identityID ?? identityID,
                    isIncognito: priorRecord?.isIncognito ?? isPrivateSession,
                    createdAt: priorRecord?.createdAt ?? .now,
                    mimeType: response.mimeType ?? priorRecord?.mimeType,
                    typeIdentifier: contentType?.identifier ?? priorRecord?.typeIdentifier,
                    expectedByteCount: response.expectedContentLength >= 0
                        ? response.expectedContentLength
                        : priorRecord?.expectedByteCount,
                    sourcePageURL: priorRecord?.sourcePageURL ?? webView.url,
                    sourceFaviconURL: priorRecord?.sourceFaviconURL
                        ?? latestPageMetadata.faviconURL
                        ?? URLResolver.conventionalFaviconURL(for: webView.url ?? sourceURL),
                    roleIDs: priorRecord?.roleIDs
                )
            )
            showDownloadNotice(
                "Downloading \(destination.lastPathComponent)",
                systemImage: "arrow.down.circle"
            )
            completionHandler(destination)
        } catch {
            cleanupDownload(id)
            completionHandler(nil)
            onDownloadFailed?(id, error.localizedDescription, false, nil)
            showDownloadNotice("Download could not start", systemImage: "exclamationmark.circle", isFailure: true)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = downloadIDs[ObjectIdentifier(download)] else { return }
        let filename = downloadFilenames[id] ?? "File"
        let fileURL = downloadDirectory.appendingPathComponent(filename, isDirectory: false)
        let byteCount: Int64?
        if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? fileHandle.close() }
            byteCount = (try? fileHandle.seekToEnd()).flatMap(Int64.init(exactly:))
        } else {
            byteCount = nil
        }
        cleanupDownload(id)
        onDownloadFinished?(id, byteCount, .now)
        showDownloadNotice("Downloaded \(filename)", systemImage: "checkmark.circle.fill")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let id = downloadIDs[ObjectIdentifier(download)] else { return }
        let retryRecord = retryDownloadRecords[id]
        let shouldRestartFresh = resumedRetryIDs.contains(id)
            && resumeData == nil
            && (error as NSError).code != NSURLErrorCancelled
        cleanupDownload(id)
        if shouldRestartFresh, let retryRecord {
            startFreshRetry(retryRecord)
            return
        }
        let cancelled = (error as NSError).code == NSURLErrorCancelled
        onDownloadFailed?(id, error.localizedDescription, cancelled, resumeData)
        showDownloadNotice(
            cancelled ? "Download cancelled" : "Download failed",
            systemImage: cancelled ? "xmark.circle" : "exclamationmark.circle",
            isFailure: !cancelled
        )
    }
}

struct PageVisualMetadata: Equatable {
    var pageTitle: String? = nil
    var siteName: String? = nil
    var faviconURL: URL? = nil
    var previewImageURL: URL? = nil
    var snapshotJPEGData: Data? = nil
}

extension WebPage: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        notifyContentInteraction()
        chromeBars.beginScroll(
            offset: normalizedOffset(for: scrollView),
            contentHeight: scrollView.contentSize.height,
            viewportHeight: scrollView.bounds.height
        )
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        chromeBars.updateScroll(
            offset: normalizedOffset(for: scrollView),
            contentHeight: scrollView.contentSize.height,
            viewportHeight: scrollView.bounds.height,
            isZooming: scrollView.isZooming
        )
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            chromeBars.endScroll()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        chromeBars.endScroll()
    }

    func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        chromeBars.show(animated: false)
    }

    private func normalizedOffset(for scrollView: UIScrollView) -> CGFloat {
        scrollView.contentOffset.y + scrollView.adjustedContentInset.top
    }
}

enum ReaderError: LocalizedError {
    case noPage
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .noPage: "There is no page to read."
        case .extractionFailed: "This page could not be converted to Reader."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
