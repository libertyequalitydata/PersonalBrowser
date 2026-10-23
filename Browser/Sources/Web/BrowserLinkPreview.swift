import SwiftUI
import WebKit

@MainActor
final class BrowserSubtabPage: NSObject, ObservableObject {
    let webView: WKWebView
    private let sourceIdentityID: UUID?

    @Published private(set) var url: URL?
    @Published private(set) var title = "Subtab"
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    var onOpenAsTab: ((URL) -> Void)?

    init(sourcePage: WebPage, url: URL?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sourcePage.webView.configuration.websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        sourceIdentityID = sourcePage.readerIdentityID
        self.url = url
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .onDrag
        if let url {
            webView.load(BrowserLanguage.request(for: url))
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
        updateState()
    }

    func stop() {
        webView.stopLoading()
        onOpenAsTab = nil
    }

    @discardableResult
    func navigate(_ input: String) -> Bool {
        guard let destination = URLResolver.resolve(input) else { return false }
        errorMessage = nil
        webView.load(BrowserLanguage.request(for: destination))
        return true
    }

    func openCurrentAsTab() {
        guard let currentURL = webView.url ?? url else { return }
        onOpenAsTab?(currentURL)
    }

    func extractReaderDocument() async throws -> ReaderDocument {
        try await WebPage.extractReaderDocument(
            from: webView,
            fallbackTitle: title,
            identityID: sourceIdentityID
        )
    }

    private func updateState() {
        url = webView.url ?? url
        let trimmedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmedTitle?.isEmpty == false ? trimmedTitle! : (url?.host ?? "Subtab")
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }
}

extension BrowserSubtabPage: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let destination = navigationAction.request.url else { return .allow }
        if BrowserNavigationDestinationPolicy.decision(
            for: destination,
            currentURL: webView.url,
            navigationType: navigationAction.navigationType
        ) == .handleExternalApp {
            onOpenAsTab?(destination)
            return .cancel
        }
        if navigationAction.shouldPerformDownload {
            onOpenAsTab?(destination)
            return .cancel
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        guard !navigationResponse.canShowMIMEType else { return .allow }
        if let destination = navigationResponse.response.url {
            onOpenAsTab?(destination)
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        updateState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        errorMessage = error.localizedDescription
        updateState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        errorMessage = error.localizedDescription
        updateState()
    }
}

extension BrowserSubtabPage: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let requestURL = navigationAction.request.url {
            webView.load(BrowserLanguage.request(for: requestURL))
        }
        return nil
    }
}

struct BrowserSubtabPanel: View {
    @StateObject private var page: BrowserSubtabPage
    @State private var address: String
    @State private var addressFocused = false
    @State private var didCopyURL = false
    @State private var presentationMode: PagePresentationMode = .web
    @State private var readerDocument: ReaderDocument?
    @State private var isExtractingReader = false
    @StateObject private var readerActions = ReaderActionVisibilityModel()
    private let startsBlank: Bool
    private let isIncognito: Bool
    let onOpenAsTab: (URL) -> Void
    let onDismiss: () -> Void

    init(
        sourcePage: WebPage,
        request: BrowserSubtabRequest,
        isIncognito: Bool,
        onOpenAsTab: @escaping (URL) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _page = StateObject(
            wrappedValue: BrowserSubtabPage(
                sourcePage: sourcePage,
                url: request.url
            )
        )
        _address = State(initialValue: request.url?.absoluteString ?? "")
        startsBlank = request.url == nil
        self.isIncognito = isIncognito
        self.onOpenAsTab = onOpenAsTab
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                if presentationMode == .reader, let readerDocument {
                    InlineReaderSurface(
                        document: readerDocument,
                        onScrollOffsetChange: { readerActions.update(offset: $0) },
                        onDragTranslationChange: {
                            readerActions.updateDrag(translationHeight: $0)
                        }
                    )
                } else if page.url == nil && !page.isLoading {
                    subtabStart
                } else {
                    BrowserSubtabWebView(webView: page.webView)
                        .onTapGesture(perform: dismissAddressEditing)
                }

                if page.isLoading || isExtractingReader {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                        .padding(.top, 12)
                }
            }

            Divider()
            controls
        }
        .background(subtabCanvas)
        .preferredColorScheme(isIncognito ? .dark : .light)
        .onAppear {
            page.onOpenAsTab = { url in
                onOpenAsTab(url)
            }
            if startsBlank {
                DispatchQueue.main.async {
                    addressFocused = true
                }
            }
        }
        .onDisappear { page.stop() }
        .onChange(of: page.url) { oldURL, newURL in
            guard !addressFocused else { return }
            address = newURL?.absoluteString ?? ""
            if oldURL != newURL,
               let readerDocument,
               readerDocument.sourceURL != newURL {
                presentationMode = .web
                self.readerDocument = nil
                readerActions.reset()
            }
        }
        .onChange(of: addressFocused) { _, focused in
            if focused {
                address = page.url?.absoluteString ?? address
            }
        }
        .alert("Subtab", isPresented: errorPresented) {
            Button("Open as Tab") { page.openCurrentAsTab() }
            Button("Close", role: .cancel) { page.errorMessage = nil }
        } message: {
            Text(page.errorMessage ?? "The page could not be opened in this Subtab.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Subtab")

            if presentationMode == .reader {
                Spacer(minLength: 0)
            } else if page.url == nil && !page.isLoading {
                Spacer(minLength: 0)
            } else {
                compactAddressField
            }

            Button(action: page.openCurrentAsTab) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(page.url == nil)
            .opacity(page.url == nil ? 0.35 : 1)
            .accessibilityLabel("Open as Tab")
        }
        .foregroundStyle(primaryForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(subtabCanvas)
    }

    private var subtabStart: some View {
        ZStack {
            subtabCanvas
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissAddressEditing)

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: BrowserSubtabStartPresentation.systemImage)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(Color.browserAccent)

                    Text(BrowserSubtabStartPresentation.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(primaryForeground)

                    Text(BrowserSubtabStartPresentation.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(secondaryForeground)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }

                centralAddressField
            }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .offset(y: -20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactAddressField: some View {
        HStack(spacing: 8) {
            Image(systemName: isIncognito ? "eye.slash.fill" : "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(secondaryForeground)

            AddressBarTextField(
                text: $address,
                isFocused: $addressFocused,
                inactiveText: AddressBarPresentation.inactiveText(for: page.url),
                textColor: fieldTextColor,
                tintColor: fieldTintColor,
                onSubmit: navigate
            )
            .frame(height: 40)

            if addressFocused {
                Button(action: copyCurrentURL) {
                    Image(systemName: didCopyURL ? "checkmark" : "doc.on.doc")
                        .frame(width: 32, height: 32)
                }
                .disabled(page.url == nil)
                .accessibilityLabel(didCopyURL ? "URL copied" : "Copy URL")

                Button(action: clearAddress) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 32, height: 32)
                }
                .disabled(address.isEmpty)
                .accessibilityLabel("Clear address")
            } else if page.isLoading {
                Button(action: page.stopLoading) {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Stop loading")
            } else {
                Button(action: page.reload) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Reload")
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(addressFieldBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(addressFieldStroke, lineWidth: 1)
        }
        .onTapGesture { addressFocused = true }
    }

    private var centralAddressField: some View {
        HStack(spacing: 8) {
            Image(systemName: isIncognito ? "eye.slash.fill" : "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(secondaryForeground)
                .frame(width: 28, height: 44)

            AddressBarTextField(
                text: $address,
                isFocused: $addressFocused,
                inactiveText: "",
                textColor: fieldTextColor,
                tintColor: fieldTintColor,
                onSubmit: navigate,
                placeholder: AddressBarPresentation.newTabPlaceholder,
                fontSize: 17
            )
            .frame(height: 44)

            if !address.isEmpty {
                Button(action: clearAddress) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(secondaryForeground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear address")
            }

            if addressFocused {
                Button(action: dismissAddressEditing) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(secondaryForeground)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(addressFieldBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(addressFieldStroke, lineWidth: 1.25)
        }
        .shadow(color: Color.browserInk.opacity(0.08), radius: 14, y: 5)
        .onTapGesture { addressFocused = true }
        .accessibilityLabel(AddressBarPresentation.newTabPlaceholder)
    }

    private var controls: some View {
        HStack(spacing: 0) {
            if presentationMode == .reader {
                Color.clear.frame(width: 44, height: 44)
                Spacer()
                previewControl(
                    "View webpage",
                    systemImage: "globe",
                    action: showWebpage
                )
                Spacer()
                previewControl(
                    "Open as Tab",
                    systemImage: "square.on.square",
                    enabled: page.url != nil,
                    action: page.openCurrentAsTab
                )
            } else {
                previewControl(
                    "Back",
                    systemImage: "chevron.backward",
                    enabled: page.canGoBack,
                    action: page.goBack
                )
                Spacer()
                previewControl(
                    "Forward",
                    systemImage: "chevron.forward",
                    enabled: page.canGoForward,
                    action: page.goForward
                )
                Spacer()
                Button(action: activateReader) {
                    Group {
                        if isExtractingReader {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "eyeglasses")
                                .font(.system(size: 20, weight: .medium))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(page.url == nil || page.isLoading || isExtractingReader)
                .opacity(page.url == nil || page.isLoading ? 0.35 : 1)
                .accessibilityLabel("Open Reader")
                Spacer()
                previewControl(
                    "Open as Tab",
                    systemImage: "square.on.square",
                    enabled: page.url != nil,
                    action: page.openCurrentAsTab
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(isIncognito ? Color.incognitoChrome : Color.browserCanvas)
    }

    private func previewControl(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(title)
    }

    private func navigate() {
        guard page.navigate(address) else { return }
        addressFocused = false
    }

    private func activateReader() {
        guard !isExtractingReader else { return }
        if readerDocument?.sourceURL == page.url {
            readerActions.reset()
            presentationMode = .reader
            return
        }

        isExtractingReader = true
        Task {
            defer { isExtractingReader = false }
            do {
                readerDocument = try await page.extractReaderDocument()
                readerActions.reset()
                presentationMode = .reader
                addressFocused = false
            } catch {
                page.errorMessage = error.localizedDescription
            }
        }
    }

    private func showWebpage() {
        readerActions.reset()
        presentationMode = .web
    }

    private func copyCurrentURL() {
        guard let url = page.url else { return }
        UIPasteboard.general.string = url.absoluteString
        didCopyURL = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopyURL = false
        }
    }

    private func clearAddress() {
        address = ""
        addressFocused = true
        didCopyURL = false
    }

    private func dismissAddressEditing() {
        addressFocused = false
    }

    private var subtabCanvas: Color {
        isIncognito ? .incognitoCanvas : .browserCanvas
    }

    private var primaryForeground: Color {
        isIncognito ? .white : .browserInk
    }

    private var secondaryForeground: Color {
        isIncognito ? Color.white.opacity(0.68) : .secondary
    }

    private var addressFieldBackground: Color {
        isIncognito ? .incognitoSurface : .browserAddressField
    }

    private var addressFieldStroke: Color {
        isIncognito
            ? Color.white.opacity(addressFocused ? 0.34 : 0.12)
            : Color.browserAccent.opacity(addressFocused ? 0.35 : 0.08)
    }

    private var fieldTextColor: UIColor {
        isIncognito ? .white : UIColor(Color.browserInk)
    }

    private var fieldTintColor: UIColor {
        isIncognito ? .white : UIColor(Color.browserAccent)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { page.errorMessage != nil },
            set: { if !$0 { page.errorMessage = nil } }
        )
    }
}

enum BrowserSubtabStartPresentation {
    static let systemImage = "macwindow.on.rectangle"
    static let title = "Quick Visit"
    static let subtitle = "Search or open a site without leaving the tab underneath."
}

private struct BrowserSubtabWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
