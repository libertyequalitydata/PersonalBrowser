import SwiftUI
import UIKit

private struct BrowserPageWebSurfaceActivityState: Equatable {
    let isWebMode: Bool
    let isDrawerPresented: Bool
    let isHomeScreenSharePresented: Bool
    let isSharePresented: Bool
    let isQuickSwitcherPresented: Bool
    let subtabRequestID: UUID?

    var isActive: Bool {
        isWebMode
            && !isDrawerPresented
            && !isHomeScreenSharePresented
            && !isSharePresented
            && !isQuickSwitcherPresented
            && subtabRequestID == nil
    }
}

private struct BrowserRootVisibilityState: Equatable {
    let showingTabs: Bool
    let showingLibrary: Bool
    let showingInsights: Bool
    let showingAbout: Bool
    let showingOnboarding: Bool
    let showingMediaPlayer: Bool
    let showingPDF: Bool

    var showsLivePageContainer: Bool {
        !showingTabs
            && !showingLibrary
            && !showingInsights
            && !showingAbout
            && !showingOnboarding
            && !showingMediaPlayer
            && !showingPDF
    }
}

enum BrowserRootSurfacePolicy {
    static func isBrowserSurfaceObscured(
        showingLibrary: Bool,
        showingInsights: Bool,
        showingAbout: Bool,
        showingOnboarding: Bool,
        showingMediaPlayer: Bool,
        showingPDF: Bool
    ) -> Bool {
        showingLibrary
            || showingInsights
            || showingAbout
            || showingOnboarding
            || showingMediaPlayer
            || showingPDF
    }

    static func exposesUnderlyingBrowser(
        showingLibrary: Bool,
        showingInsights: Bool,
        showingAbout: Bool,
        showingOnboarding: Bool,
        showingMediaPlayer: Bool,
        showingPDF: Bool
    ) -> Bool {
        !isBrowserSurfaceObscured(
            showingLibrary: showingLibrary,
            showingInsights: showingInsights,
            showingAbout: showingAbout,
            showingOnboarding: showingOnboarding,
            showingMediaPlayer: showingMediaPlayer,
            showingPDF: showingPDF
        )
    }
}

struct BrowserRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var mediaPlayback: BrowserMediaPlaybackController
    @EnvironmentObject private var documentViewer: BrowserDocumentViewerController
    @EnvironmentObject private var transcription: BrowserTranscriptionController
    @AppStorage("BrowserOnboardingVersion") private var completedOnboardingVersion = 0
    @State private var showingTabs = false
    @State private var showingReadingList = false
    @State private var showingBrowsingInsights = false
    @State private var showingAbout = false
    @State private var webpageRevealRequestID = UUID()
    @State private var showingOnboarding = false

    var body: some View {
        ZStack {
            Group {
                if showingTabs {
                    TabOverviewView(
                        sourceTabID: store.selectedTabID,
                        onDone: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingTabs = false
                            }
                        },
                        onShowReadingList: {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showingTabs = false
                                showingReadingList = true
                            }
                        }
                    )
                    .transition(.move(edge: .trailing))
                } else if let tab = store.selectedTab {
                    BrowserPageView(
                        tab: tab,
                        page: store.page(for: tab),
                        showingTabs: $showingTabs,
                        showingReadingList: $showingReadingList,
                        onOpenBrowsingInsights: {
                            store.checkpointAttention()
                            showingBrowsingInsights = true
                        },
                        onOpenAbout: { showingAbout = true },
                        onReplayOnboarding: { showingOnboarding = true },
                        onboardingIsPresented: completedOnboardingVersion < 1 || showingOnboarding,
                        browserSurfaceIsObscured: browserSurfaceIsObscured,
                        webpageRevealRequestID: webpageRevealRequestID
                    )
                    .id(tab.id)
                } else {
                    ProgressView()
                }
            }
            .allowsHitTesting(exposesUnderlyingBrowser)
            .accessibilityHidden(!exposesUnderlyingBrowser)

            if showingReadingList {
                LibraryView(
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showingReadingList = false
                        }
                    },
                    onViewOriginal: { document in
                        store.open(
                            document.sourceURL,
                            preferredIdentityID: document.capturedIdentityID
                        )
                        webpageRevealRequestID = UUID()
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showingReadingList = false
                        }
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }

            if showingBrowsingInsights {
                BrowsingInsightsView {
                    showingBrowsingInsights = false
                }
                .environmentObject(store)
                .transition(.move(edge: .trailing))
                .zIndex(3)
            }

            if showingAbout {
                BrowserAboutView(onBack: { showingAbout = false })
                    .transition(.move(edge: .trailing))
                    .zIndex(4)
            }

            if let notice = store.downloadNotice {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        Label(notice.message, systemImage: notice.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(
                                notice.isFailure ? Color.red.opacity(0.92) : Color.browserInk.opacity(0.92),
                                in: Capsule()
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
                            .padding(.horizontal, 16)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 88)
                    }
                }
                .id(notice.id)
                .allowsHitTesting(false)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(20)
            }

            if !showingTabs,
               !showingReadingList,
               !showingAbout,
               mediaPlayback.currentItem != nil,
               mediaPlayback.presentedItem == nil {
                GeometryReader { geometry in
                    VStack {
                        Spacer()
                        BrowserMediaMiniPlayer(playback: mediaPlayback)
                            .padding(.horizontal, 12)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 78)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(16)
            }

            if mediaPlayback.presentedItem != nil {
                BrowserMediaPlayerScreen(
                    playback: mediaPlayback,
                    onTranscribe: transcribeCurrentMedia
                )
                    .transition(.opacity)
                    .zIndex(100)
            }

            if let pdf = documentViewer.presentedPDF {
                BrowserPDFViewerScreen(item: pdf, onDismiss: documentViewer.dismiss)
                    .transition(.opacity)
                    .zIndex(101)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.downloadNotice?.id)
        .background(Color.browserCanvas)
        .fullScreenCover(isPresented: $showingOnboarding) {
            BrowserOnboardingView {
                completedOnboardingVersion = 1
                showingOnboarding = false
            }
        }
        .onAppear {
            mediaPlayback.onPlaybackTime = { item, seconds, date in
                store.recordMediaPlayback(item, seconds: seconds, at: date)
            }
            store.setApplicationActive(scenePhase == .active)
            updateWebContentVisibility()
            if completedOnboardingVersion < 1 {
                showingOnboarding = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            store.setApplicationActive(phase == .active)
        }
        .onChange(of: rootVisibilityState) { _, _ in updateWebContentVisibility() }
        .onOpenURL(perform: openExternalWebURL)
        .alert("Local data could not be saved", isPresented: persistenceAlert) {
            Button("OK") { store.persistenceError = nil }
        } message: {
            Text(store.persistenceError ?? "Unknown error")
        }
    }

    private var persistenceAlert: Binding<Bool> {
        Binding(
            get: { store.persistenceError != nil },
            set: { if !$0 { store.persistenceError = nil } }
        )
    }

    private func openExternalWebURL(_ url: URL) {
        guard store.openExternalWebURL(url) != nil else { return }
        showingOnboarding = false
        showingTabs = false
        showingReadingList = false
        showingBrowsingInsights = false
        showingAbout = false
        webpageRevealRequestID = UUID()
    }

    private func updateWebContentVisibility() {
        store.setWebContentVisible(rootVisibilityState.showsLivePageContainer)
    }

    private var rootVisibilityState: BrowserRootVisibilityState {
        BrowserRootVisibilityState(
            showingTabs: showingTabs,
            showingLibrary: showingReadingList,
            showingInsights: showingBrowsingInsights,
            showingAbout: showingAbout,
            showingOnboarding: showingOnboarding,
            showingMediaPlayer: mediaPlayback.presentedItem != nil,
            showingPDF: documentViewer.presentedPDF != nil
        )
    }

    private var browserSurfaceIsObscured: Bool {
        BrowserRootSurfacePolicy.isBrowserSurfaceObscured(
            showingLibrary: showingReadingList,
            showingInsights: showingBrowsingInsights,
            showingAbout: showingAbout,
            showingOnboarding: showingOnboarding,
            showingMediaPlayer: mediaPlayback.presentedItem != nil,
            showingPDF: documentViewer.presentedPDF != nil
        )
    }

    private var exposesUnderlyingBrowser: Bool {
        BrowserRootSurfacePolicy.exposesUnderlyingBrowser(
            showingLibrary: showingReadingList,
            showingInsights: showingBrowsingInsights,
            showingAbout: showingAbout,
            showingOnboarding: showingOnboarding,
            showingMediaPlayer: mediaPlayback.presentedItem != nil,
            showingPDF: documentViewer.presentedPDF != nil
        )
    }

    private func transcribeCurrentMedia(_ item: BrowserMediaItem) {
        let artifact: LibraryArtifact?
        if let artifactID = item.libraryArtifactID {
            artifact = store.libraryArtifacts.first { $0.id == artifactID }
        } else if let download = store.downloads.first(where: {
            store.downloadFileURL(for: $0) == item.url
        }) {
            artifact = try? store.addDownloadToLibrary(download)
        } else {
            artifact = nil
        }

        guard let artifact, let url = store.libraryFileURL(for: artifact) else {
            store.showNotice(
                "Add this media to Library before transcribing",
                systemImage: "books.vertical",
                isFailure: true
            )
            return
        }
        transcription.transcribe(artifact: artifact, url: url, store: store)
    }

}

private struct BrowserPageView: View {
    @EnvironmentObject private var store: BrowserStore
    let tab: BrowserTab
    @ObservedObject var page: WebPage
    @Binding var showingTabs: Bool
    @Binding var showingReadingList: Bool
    let onOpenBrowsingInsights: () -> Void
    let onOpenAbout: () -> Void
    let onReplayOnboarding: () -> Void
    let onboardingIsPresented: Bool
    let browserSurfaceIsObscured: Bool
    let webpageRevealRequestID: UUID

    @State private var address = ""
    @State private var readerDocument: ReaderDocument?
    @State private var presentationMode: PagePresentationMode = .web
    @State private var isExtracting = false
    @State private var actionError: String?
    @State private var readingListFeedback: ReadingListFeedback?
    @State private var readingListFeedbackTask: Task<Void, Never>?
    @State private var showingHiddenControlsHint = false
    @State private var showingIncognitoBookmarkConfirmation = false
    @State private var didCopyURL = false
    @StateObject private var readerActions = ReaderActionVisibilityModel()
    @State private var addressFocused = false
    @State private var isKeyboardVisible = false
    @State private var showingHomeScreenShare = false
    @State private var showingShareSheet = false
    @State private var showingHomeScreenUnavailable = false
    @State private var showingQuickSwitcher = false
    @State private var showingPageActionsDrawer = false
    @State private var readerSharePayload: ReaderSharePayload?
    @State private var isExportingReaderPDF = false
    @State private var minimizedControlIsDragging = false
    @GestureState private var minimizedControlDragOffset: CGFloat = 0
    @AppStorage("MinimizedBrowserControlsSide") private var minimizedControlsSideRawValue = MinimizedControlSide.trailing.rawValue

    @ViewBuilder
    private func browserSurface(geometry: GeometryProxy) -> some View {
        ZStack {
            if isBlankTab {
                NewTabView(
                    address: $address,
                    addressFocused: $addressFocused,
                    isIncognito: tab.isPrivate,
                    onSubmit: navigate,
                    onDismissKeyboard: dismissAddressEditing,
                    onToggleIncognito: toggleBlankTabPrivacy
                )
            } else if presentationMode == .reader, let readerDocument {
                InlineReaderSurface(
                    document: readerDocument,
                    onScrollOffsetChange: { readerActions.update(offset: $0) },
                    onDragTranslationChange: { readerActions.updateDrag(translationHeight: $0) }
                )
            } else {
                WebView(page: page)
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
            }

            if presentationMode == .web,
               page.usesSiteBottomNavigation,
               page.siteAccessibilitySupport?.domainKey == "facebook.com",
               !isKeyboardVisible,
               !isBlankTab {
                VStack(spacing: 0) {
                    Spacer()
                    facebookAccessibilityFooter
                }
                .padding(
                    .bottom,
                    FacebookAccessibilityFooterLayout.bottomPadding(
                        safeAreaBottom: geometry.safeAreaInsets.bottom,
                        browserToolbarHeight: footerLayoutHeight(
                            safeAreaBottom: geometry.safeAreaInsets.bottom
                        )
                    )
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            if presentationMode.showsBrowserChrome, page.isLoading {
                VStack {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.browserAccent)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: Color.browserAccent.opacity(0.12), radius: 12, y: 4)
                    Spacer()
                }
                .padding(.top, 12)
            }

            if presentationMode.showsBrowserChrome, showingHiddenControlsHint {
                VStack {
                    Spacer()
                    Label("Tap the floating button for Pinned Tabs", systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.browserInk.opacity(0.9), in: Capsule())
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
            }

            if let readingListFeedback {
                VStack {
                    Spacer()
                    Label(readingListFeedback.message, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.browserInk.opacity(0.94), in: Capsule())
                        .shadow(color: Color.black.opacity(0.14), radius: 14, y: 5)
                        .padding(.horizontal, 20)
                        .padding(
                            .bottom,
                            readingListFeedbackBottomPadding(
                                safeAreaBottom: geometry.safeAreaInsets.bottom
                            )
                        )
                        .transition(
                            .move(edge: .bottom)
                                .combined(with: .scale(scale: 0.92))
                                .combined(with: .opacity)
                        )
                }
                .id(readingListFeedback.id)
                .allowsHitTesting(false)
                .zIndex(4)
            }

            if presentationMode.showsReaderActions {
                VStack {
                    Spacer()
                    readerActionBar
                        .offset(y: readerActions.isVisible ? 0 : 76)
                        .opacity(readerActions.isVisible ? 1 : 0)
                        .allowsHitTesting(readerActions.isVisible)
                        .animation(.easeOut(duration: 0.18), value: readerActions.isVisible)
                        .padding(
                            .bottom,
                            ReaderFloatingLayout.inlineBottomPadding(
                                safeAreaBottom: geometry.safeAreaInsets.bottom
                            )
                        )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

            if presentationMode == .web,
               page.browserControlsPinnedHidden,
               !isKeyboardVisible,
               !isBlankTab {
                VStack {
                    Spacer()
                    minimizedBrowserControlsRow(containerWidth: geometry.size.width)
                }
                .padding(.horizontal, MinimizedControlPlacement.horizontalInset)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 32)
                .transition(
                    .scale(
                        scale: 0.86,
                        anchor: minimizedControlsSide == .trailing ? .bottomTrailing : .bottomLeading
                    )
                    .combined(with: .opacity)
                )
                .zIndex(6)
            }
        }
    }

    private var coreLayout: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if presentationMode.showsBrowserChrome, !isBlankTab {
                    header
                        .frame(height: headerHeight, alignment: .bottom)
                        .clipped()
                        .allowsHitTesting(chromeProgress > 0.9)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                browserSurface(geometry: geometry)

                if presentationMode.showsBrowserChrome {
                    toolbar(safeAreaBottom: geometry.safeAreaInsets.bottom)
                        .frame(
                            height: footerLayoutHeight(
                                safeAreaBottom: geometry.safeAreaInsets.bottom
                            ),
                            alignment: .top
                        )
                        .clipped()
                        .opacity(isKeyboardVisible ? 0 : chromeProgress)
                        .allowsHitTesting(!isKeyboardVisible && chromeProgress > 0.9)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background {
            chromeBackground.ignoresSafeArea()
        }
        .overlay {
            ZStack {
                if showingPageActionsDrawer {
                    PageActionsDrawer(
                        isPresented: $showingPageActionsDrawer,
                        page: page,
                        isPrivate: tab.isPrivate,
                        isBookmarked: store.isBookmarked(page.url),
                        isPinned: tab.isPinned,
                        linkOpeningPolicy: page.linkOpeningPolicy,
                        menusAreMinimized: page.browserControlsPinnedHidden,
                        canUsePageActions: page.url != nil,
                        canToggleMenus: page.url != nil && presentationMode == .web,
                        canPin: !tab.isPrivate,
                        canAddToHomeScreen: page.url != nil && !tab.isPrivate,
                        onToggleBookmark: {
                            presentAfterClosingPageActions(action: toggleBookmark)
                        },
                        onShare: {
                            presentAfterClosingPageActions { showingShareSheet = true }
                        },
                        onAddToHomeScreen: {
                            presentAfterClosingPageActions(action: addToHomeScreen)
                        },
                        onTogglePinned: {
                            presentAfterClosingPageActions(action: togglePinnedTab)
                        },
                        onSetLinkOpeningPolicy: { policy in
                            store.setLinkOpeningPolicy(policy, for: tab.id)
                        },
                        onNewTab: {
                            presentAfterClosingPageActions(action: createNewTab)
                        },
                        onOpenTabs: {
                            presentAfterClosingPageActions {
                                showingTabs = true
                            }
                        },
                        onCloseCurrentTab: {
                            presentAfterClosingPageActions {
                                store.closeTab(tab.id)
                            }
                        },
                        onOpenLibrary: {
                            presentAfterClosingPageActions {
                                showingReadingList = true
                            }
                        },
                        onOpenBrowsingInsights: {
                            presentAfterClosingPageActions(action: onOpenBrowsingInsights)
                        },
                        onToggleMenus: {
                            presentAfterClosingPageActions(action: toggleBrowserControls)
                        },
                        onReplayOnboarding: {
                            presentAfterClosingPageActions(action: onReplayOnboarding)
                        },
                        onOpenAbout: {
                            onOpenAbout()
                            showingPageActionsDrawer = false
                        }
                    )
                    .environmentObject(store)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(9)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showingPageActionsDrawer)
        .environment(\.colorScheme, presentationMode == .reader ? .light : (tab.isPrivate ? .dark : .light))
    }

    var body: some View {
        coreLayout
        .onAppear {
            syncAddress()
            page.onContentInteraction = {
                store.recordContentInteraction(for: tab.id)
                dismissAddressEditing()
            }
            page.onQuickSwitcherRequested = {
                showingQuickSwitcher = true
            }
            if BrowserInitialFocusPolicy.shouldFocusBlankTab(
                isBlankTab: tab.url == nil && page.url == nil,
                onboardingIsPresented: onboardingIsPresented,
                browserSurfaceIsObscured: browserSurfaceIsObscured
            ) {
                DispatchQueue.main.async {
                    addressFocused = true
                }
            }
            reportWebSurfaceActivity()
        }
        .onDisappear {
            store.setSelectedPageWebSurfaceActive(false)
            page.onContentInteraction = nil
            page.onQuickSwitcherRequested = nil
        }
        .onChange(of: page.url) { oldURL, newURL in
            syncAddress()
            if oldURL != newURL {
                presentationMode = .web
                readerDocument = nil
                readerActions.reset()
            }
        }
        .onChange(of: page.title) { _, _ in syncAddressIfNotFocused() }
        .onChange(of: webSurfaceActivityState) { _, _ in
            reportWebSurfaceActivity()
        }
        .onChange(of: webpageRevealRequestID) { _, _ in
            readerActions.reset()
            presentationMode = .web
            readerDocument = nil
            page.chromeBars.show()
        }
        .onChange(of: onboardingIsPresented) { _, isPresented in
            if isPresented {
                dismissAddressEditing()
            }
        }
        .onChange(of: browserSurfaceIsObscured) { _, isObscured in
            if isObscured {
                dismissAddressEditing()
            }
        }
        .onChange(of: addressFocused) { _, focused in
            if focused {
                address = page.url?.absoluteString ?? address
                page.chromeBars.show()
            } else {
                syncAddress()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.16)) {
                isKeyboardVisible = false
            }
        }
        .alert("Browser", isPresented: errorAlert) {
            Button("OK") { actionError = nil; page.errorMessage = nil }
        } message: {
            Text(actionError ?? page.presentableErrorMessage ?? "Unknown error")
        }
        .alert(
            externalAppLinkPromptTitle,
            isPresented: externalAppLinkPromptPresented,
            presenting: page.pendingExternalAppLinkRequest
        ) { request in
            Button("Stay in Browser") {
                page.chooseExternalAppLink(.stayInBrowser, request: request)
            }
            Button(request.openActionTitle) {
                page.chooseExternalAppLink(.openApp, request: request)
            }
        } message: { request in
            Text("Browser will remember this choice for \(request.serviceName). You can change it later in Site Settings.")
        }
        .alert("Save this Incognito page?", isPresented: $showingIncognitoBookmarkConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Save") { store.addBookmarkForSelectedPage() }
        } message: {
            Text("This saved page will remain after the Incognito session ends and will appear only in Incognito Saved Bookmarks.")
        }
        .alert("Keep this sign-in?", isPresented: signInOfferPresented) {
            Button("Not Now", role: .cancel) {
                page.dismissSignInOffer()
            }
            Button("Open Incognito") {
                openSignInPageIncognito()
            }
            Button("Keep Signed In") {
                page.keepSignInSession()
            }
        } message: {
            Text(signInOfferMessage)
        }
        .sheet(isPresented: $showingHomeScreenShare) {
            WebsiteHomeScreenActivityView(webView: page.webView)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = page.url {
                URLShareActivityView(url: url)
            }
        }
        .sheet(isPresented: $showingQuickSwitcher) {
            PinnedTabQuickSwitcherView(
                currentTabID: tab.id,
                canSave: page.url != nil,
                isSaved: store.isBookmarked(page.url),
                menusAreMinimized: page.browserControlsPinnedHidden,
                onSelect: { tabID in
                    showingQuickSwitcher = false
                    store.selectTab(tabID)
                },
                onSave: {
                    showingQuickSwitcher = false
                    DispatchQueue.main.async {
                        toggleBookmark()
                    }
                },
                onNewTab: {
                    showingQuickSwitcher = false
                    DispatchQueue.main.async {
                        createNewTab()
                    }
                },
                onOpenSubtab: {
                    showingQuickSwitcher = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        page.openSubtab()
                    }
                },
                onOpenTabs: {
                    showingQuickSwitcher = false
                    DispatchQueue.main.async {
                        showingTabs = true
                    }
                },
                onToggleMenus: {
                    showingQuickSwitcher = false
                    DispatchQueue.main.async {
                        toggleBrowserControls()
                    }
                },
                onOpenMainMenu: {
                    showingQuickSwitcher = false
                    DispatchQueue.main.async {
                        showingPageActionsDrawer = true
                    }
                },
                onDismiss: {
                    showingQuickSwitcher = false
                }
            )
            .environmentObject(store)
            .presentationDetents([
                .height(
                    PinnedTabQuickSwitcherPresentation.sheetHeight(
                        itemCount: store.pinnedTabs.count
                    )
                )
            ])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.light)
        }
        .sheet(item: $page.pendingSubtabRequest) { request in
            BrowserSubtabPanel(
                sourcePage: page,
                request: request,
                isIncognito: tab.isPrivate,
                onOpenAsTab: { url in
                    page.dismissSubtab()
                    let newTab = store.createTab(
                        identityID: tab.identityID,
                        roleIDs: tab.roleIDs,
                        isPrivate: tab.isPrivate,
                        url: url,
                        select: true
                    )
                    _ = store.page(for: newTab)
                },
                onDismiss: page.dismissSubtab
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
        }
        .sheet(item: $readerSharePayload) { payload in
            ReaderShareActivityView(payload: payload)
        }
        .alert("Add to Home Screen is unavailable", isPresented: $showingHomeScreenUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(BrowserCapabilityPresentation.addToHomeScreenAlert)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.isPrivate ? "eye.slash.fill" : "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tab.isPrivate ? Color.white : Color.secondary)

            AddressBarTextField(
                text: $address,
                isFocused: $addressFocused,
                inactiveText: AddressBarPresentation.inactiveText(for: page.url),
                textColor: tab.isPrivate ? .white : UIColor(Color.browserInk),
                tintColor: tab.isPrivate ? .white : UIColor(Color.browserAccent),
                onSubmit: navigate
            )

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
                }
                .accessibilityLabel("Stop loading")
            } else if page.url != nil {
                Button(action: page.reload) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(
            tab.isPrivate ? Color.incognitoSurface : Color.browserAddressField,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    tab.isPrivate
                        ? Color.white.opacity(addressFocused ? 0.34 : 0.12)
                        : Color.browserAccent.opacity(addressFocused ? 0.35 : 0.08),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.browserInk.opacity(0.06), radius: 10, y: 3)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(chromeBackground.ignoresSafeArea(edges: .top))
    }

    private func toolbar(safeAreaBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            toolbarControls
                .padding(.horizontal, 4)
                .frame(height: BrowserChromeLayout.footerControlHeight)

            Color.clear
                .frame(height: max(safeAreaBottom, 0))
        }
        .frame(maxWidth: .infinity)
        .background(chromeBackground)
        .overlay(alignment: .top) {
            Divider()
                .opacity(tab.isPrivate ? 0.28 : 0.55)
        }
    }

    private var toolbarControls: some View {
        HStack(spacing: 0) {
            footerButton(action: page.goBack) { Image(systemName: "chevron.backward") }
                .disabled(!page.canGoBack)
                .accessibilityLabel("Back")

            footerButton(action: page.goForward) { Image(systemName: "chevron.forward") }
                .disabled(!page.canGoForward)
                .accessibilityLabel("Forward")

            footerButton(action: addToReadingList) {
                Group {
                    if isExtracting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "text.badge.plus")
                    }
                }
            }
            .disabled(page.url == nil || isExtracting)
            .accessibilityLabel("Add to Library")

            footerButton(action: togglePresentationMode) {
                Group {
                    if isExtracting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "eyeglasses")
                    }
                }
            }
            .disabled(page.url == nil || isExtracting)
            .accessibilityLabel("Open Reader")

            footerButton(action: createNewTab) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("New Tab")

            footerButton(action: { showingTabs = true }) {
                Image(systemName: "square.on.square")
            }
            .accessibilityLabel("Tabs")

            footerSlot { pageActionsButton }
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(tab.isPrivate ? Color.white : Color.browserControl)
    }

    private var facebookAccessibilityFooter: some View {
        HStack(spacing: 0) {
            ForEach(FacebookAccessibilityDestination.allCases) { destination in
                let isSelected = destination.matches(page.url)
                Button {
                    page.navigateFacebookAccessibilityFooter(to: destination)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: destination.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(destination.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(isSelected ? Color.browserAccent : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 2)
        .background(chromeBackground.opacity(0.98))
        .overlay(alignment: .top) {
            Divider().opacity(tab.isPrivate ? 0.28 : 0.55)
        }
    }

    private var readerActionBar: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                Button(action: addReaderToReadingList) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.browserInk)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to Library")

                Menu {
                    Button(action: exportInlineReaderPDF) {
                        Label("Share Reader PDF", systemImage: "doc.richtext")
                    }
                    .disabled(isExportingReaderPDF || readerDocument == nil)

                    Button {
                        if let readerDocument {
                            readerSharePayload = .originalLink(readerDocument.sourceURL)
                        }
                    } label: {
                        Label("Share Original Link", systemImage: "link")
                    }
                    .disabled(readerDocument == nil)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.browserInk)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share Reader")
            }
            .frame(width: 96)

            Button(action: showWebpage) {
                Image(systemName: "globe")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.browserInk)
                    .frame(width: 56, height: 56)
                    .background(Color.browserAccent.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View webpage")

            HStack(spacing: 0) {
                Button(action: showReadingList) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.browserInk)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Library")
            }
            .frame(width: 96)
        }
        .padding(4)
        .background(Color.white.opacity(0.96), in: Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: Color.browserInk.opacity(0.16), radius: 16, y: 6)
    }

    private func footerButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func footerSlot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
    }

    private var pageActionsButton: some View {
        Button {
            showingPageActionsDrawer = true
        } label: {
            Group {
                if isExtracting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: PinnedTabQuickSwitcherPresentation.mainMenuSystemImage)
                        .rotationEffect(
                            .degrees(PinnedTabQuickSwitcherPresentation.mainMenuRotationDegrees)
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PinnedTabQuickSwitcherPresentation.mainMenuTitle)
    }

    private func minimizedBrowserControlsRow(containerWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if minimizedControlsSide == .trailing {
                Spacer(minLength: 0)
            }

            minimizedBrowserControls(containerWidth: containerWidth)
                .offset(x: minimizedControlDragOffset)

            if minimizedControlsSide == .leading {
                Spacer(minLength: 0)
            }
        }
    }

    private func minimizedBrowserControls(containerWidth: CGFloat) -> some View {
        Button {
            showingQuickSwitcher = true
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tab.isPrivate ? Color.white : Color.browserInk)
                .frame(width: 52, height: 52)
                .background(
                    tab.isPrivate ? Color.incognitoSurface.opacity(0.96) : Color.white.opacity(0.96),
                    in: Circle()
                )
                .overlay {
                    Circle().stroke(
                        tab.isPrivate ? Color.white.opacity(0.2) : Color.browserInk.opacity(0.08)
                    )
                }
                .shadow(color: Color.black.opacity(0.16), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Pinned Tabs")
        .simultaneousGesture(minimizedControlDragGesture(containerWidth: containerWidth))
        .frame(width: 52, height: 52, alignment: minimizedControlsSide.alignment)
    }

    private func minimizedControlDragGesture(containerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($minimizedControlDragOffset) { value, state, _ in
                state = MinimizedControlPlacement.constrainedTranslation(
                    value.translation.width,
                    currentSide: minimizedControlsSide,
                    containerWidth: containerWidth
                )
            }
            .onChanged { _ in
                if !minimizedControlIsDragging {
                    minimizedControlIsDragging = true
                }
            }
            .onEnded { value in
                let targetSide = MinimizedControlPlacement.resolvedSide(
                    currentSide: minimizedControlsSide,
                    translation: value.translation.width,
                    predictedEndTranslation: value.predictedEndTranslation.width
                )
                minimizedControlIsDragging = false
                guard targetSide != minimizedControlsSide else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    minimizedControlsSideRawValue = targetSide.rawValue
                }
            }
    }

    private var minimizedControlsSide: MinimizedControlSide {
        get { MinimizedControlSide(rawValue: minimizedControlsSideRawValue) ?? .trailing }
    }

    private var chromeProgress: CGFloat {
        page.chromeProgress
    }

    private var isBlankTab: Bool {
        tab.url == nil && page.url == nil
    }

    private var headerHeight: CGFloat {
        if page.browserControlsPinnedHidden { return 0 }
        return BrowserChromeLayout.collapsedHeaderHeight
            + (BrowserChromeLayout.expandedHeaderHeight - BrowserChromeLayout.collapsedHeaderHeight) * chromeProgress
    }

    private func footerLayoutHeight(safeAreaBottom: CGFloat) -> CGFloat {
        guard !page.browserControlsPinnedHidden, !isKeyboardVisible else { return 0 }
        return BrowserChromeLayout.footerHeight(safeAreaBottom: safeAreaBottom) * chromeProgress
    }

    private var externalAppLinkPromptTitle: String {
        guard let request = page.pendingExternalAppLinkRequest else {
            return "Open this link?"
        }
        return "Open \(request.serviceName) links?"
    }

    private var externalAppLinkPromptPresented: Binding<Bool> {
        Binding(
            get: { page.pendingExternalAppLinkRequest != nil },
            set: { presented in
                if !presented {
                    page.dismissExternalAppLinkRequest()
                }
            }
        )
    }

    private var signInOfferPresented: Binding<Bool> {
        Binding(
            get: { page.signInOfferHost != nil },
            set: { if !$0 { page.dismissSignInOffer() } }
        )
    }

    private var signInOfferMessage: String {
        let host = page.signInOfferHost ?? "this site"
        return "Browser can keep you signed in to \(host) across normal browsing. Each Role can still preserve its own website account session when needed. Incognito is always excluded. The service controls when sessions expire, and passwords remain handled by iOS Passwords and AutoFill."
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { actionError != nil || page.presentableErrorMessage != nil },
            set: { if !$0 { actionError = nil; page.errorMessage = nil } }
        )
    }

    private var chromeBackground: Color {
        tab.isPrivate ? .incognitoChrome : .browserCanvas
    }

    private func navigate() {
        guard let url = URLResolver.resolve(address) else { return }
        addressFocused = false
        page.load(url)
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

    private func addToHomeScreen() {
        guard page.url != nil, !tab.isPrivate else { return }
        if BrowserEntitlementStatus.canAddToHomeScreen {
            showingHomeScreenShare = true
        } else {
            showingHomeScreenUnavailable = true
        }
    }

    private func reportWebSurfaceActivity() {
        store.setSelectedPageWebSurfaceActive(webSurfaceActivityState.isActive)
    }

    private var webSurfaceActivityState: BrowserPageWebSurfaceActivityState {
        BrowserPageWebSurfaceActivityState(
            isWebMode: presentationMode == .web,
            isDrawerPresented: showingPageActionsDrawer,
            isHomeScreenSharePresented: showingHomeScreenShare,
            isSharePresented: showingShareSheet,
            isQuickSwitcherPresented: showingQuickSwitcher,
            subtabRequestID: page.pendingSubtabRequest?.id
        )
    }

    private func dismissAddressEditing() {
        guard addressFocused else { return }
        addressFocused = false
    }

    private func openSignInPageIncognito() {
        guard let url = page.url else {
            page.dismissSignInOffer()
            return
        }
        page.dismissSignInOffer()
        let incognitoTab = store.createTab(
            roleIDs: tab.roleIDs,
            isPrivate: true,
            url: url
        )
        _ = store.page(for: incognitoTab)
    }

    private func hideBrowserControls() {
        withAnimation(.timingCurve(0, 0, 0.2, 0.1, duration: 0.2)) {
            page.hideBrowserControls()
            showingHiddenControlsHint = true
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.2)) {
                showingHiddenControlsHint = false
            }
        }
    }

    private func revealBrowserControls() {
        withAnimation(.timingCurve(0, 0, 0.2, 0.1, duration: 0.2)) {
            page.revealBrowserControls()
            showingHiddenControlsHint = false
        }
    }

    private func toggleBrowserControls() {
        if page.browserControlsPinnedHidden {
            revealBrowserControls()
        } else {
            hideBrowserControls()
        }
    }

    private func presentAfterClosingPageActions(action: @escaping () -> Void) {
        showingPageActionsDrawer = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: action)
    }

    private func togglePinnedTab() {
        store.togglePinned(tab.id)
    }

    private func createNewTab() {
        if isBlankTab {
            addressFocused = true
            return
        }
        let newTab = store.createTab(
            identityID: tab.identityID,
            roleIDs: tab.roleIDs,
            isPrivate: tab.isPrivate
        )
        _ = store.page(for: newTab)
    }

    private func toggleBlankTabPrivacy() {
        guard isBlankTab,
              let replacement = store.replaceBlankTab(tab.id, isPrivate: !tab.isPrivate) else { return }
        _ = store.page(for: replacement)
    }

    private func syncAddress() {
        guard !addressFocused else { return }
        address = page.url?.absoluteString ?? ""
    }

    private func syncAddressIfNotFocused() {
        guard !addressFocused else { return }
        address = page.url?.absoluteString ?? ""
    }

    private func activateReader() {
        if readerDocument?.sourceURL == page.url {
            readerActions.reset()
            withAnimation(.easeInOut(duration: 0.2)) {
                presentationMode = .reader
            }
            return
        }

        Task {
            await extract {
                readerDocument = $0
                readerActions.reset()
                withAnimation(.easeInOut(duration: 0.2)) {
                    presentationMode = .reader
                }
            }
        }
    }

    private func togglePresentationMode() {
        activateReader()
    }

    private func showWebpage() {
        readerActions.reset()
        withAnimation(.easeInOut(duration: 0.2)) {
            presentationMode = .web
        }
        page.chromeBars.show()
    }

    private func showReadingList() {
        withAnimation(.easeInOut(duration: 0.22)) {
            showingReadingList = true
        }
    }

    private func addToReadingList() {
        Task {
            await extract {
                showReadingListFeedback(for: store.addToReadingList($0))
            }
        }
    }

    private func addReaderToReadingList() {
        guard let readerDocument else { return }
        showReadingListFeedback(for: store.addToReadingList(readerDocument))
    }

    private func showReadingListFeedback(for mutation: ReadingListMutation) {
        readingListFeedbackTask?.cancel()
        let feedback = ReadingListFeedback(message: mutation.feedbackMessage)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            readingListFeedback = feedback
        }
        readingListFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, readingListFeedback?.id == feedback.id else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                readingListFeedback = nil
            }
        }
    }

    private func readingListFeedbackBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        guard presentationMode == .reader else { return 16 }
        return ReaderFloatingLayout.inlineBottomPadding(safeAreaBottom: safeAreaBottom) + 72
    }

    private func extract(then action: @escaping (ReaderDocument) -> Void) async {
        isExtracting = true
        defer { isExtracting = false }
        do {
            action(try await page.extractReaderDocument(identityID: tab.identityID))
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleBookmark() {
        if tab.isPrivate, !store.isBookmarked(page.url, isIncognito: true) {
            showingIncognitoBookmarkConfirmation = true
        } else {
            store.addBookmarkForSelectedPage()
        }
    }

    private func exportInlineReaderPDF() {
        guard let readerDocument, !isExportingReaderPDF else { return }
        isExportingReaderPDF = true
        Task {
            defer { isExportingReaderPDF = false }
            do {
                readerSharePayload = .exportedPDF(
                    try await ReaderPDFExporter.export(readerDocument)
                )
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

enum PageActionsDrawerDestination: Equatable {
    case menu
    case siteSettings
    case tabRoles
    case browserSettings
    case manageRoles

    var title: String {
        switch self {
        case .menu: "Menu"
        case .siteSettings: "Site Settings"
        case .tabRoles: "Tab Roles"
        case .browserSettings: "Settings"
        case .manageRoles: "Manage Roles"
        }
    }

    var parent: PageActionsDrawerDestination? {
        switch self {
        case .menu: nil
        case .siteSettings, .tabRoles, .browserSettings: .menu
        case .manageRoles: .browserSettings
        }
    }
}

private struct PageActionsDrawer: View {
    @EnvironmentObject private var store: BrowserStore
    @Binding var isPresented: Bool
    @ObservedObject var page: WebPage
    let isPrivate: Bool
    let isBookmarked: Bool
    let isPinned: Bool
    let linkOpeningPolicy: BrowserLinkOpeningPolicy
    let menusAreMinimized: Bool
    let canUsePageActions: Bool
    let canToggleMenus: Bool
    let canPin: Bool
    let canAddToHomeScreen: Bool
    let onToggleBookmark: () -> Void
    let onShare: () -> Void
    let onAddToHomeScreen: () -> Void
    let onTogglePinned: () -> Void
    let onSetLinkOpeningPolicy: (BrowserLinkOpeningPolicy) -> Void
    let onNewTab: () -> Void
    let onOpenTabs: () -> Void
    let onCloseCurrentTab: () -> Void
    let onOpenLibrary: () -> Void
    let onOpenBrowsingInsights: () -> Void
    let onToggleMenus: () -> Void
    let onReplayOnboarding: () -> Void
    let onOpenAbout: () -> Void

    @GestureState private var dragOffset: CGFloat = 0
    @State private var destination: PageActionsDrawerDestination = .menu

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    HStack {
                        if destination.parent != nil {
                            Button(action: navigateBack) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(primaryText)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Back")
                        }

                        Text(destination.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(primaryText)

                        Spacer()

                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(primaryText)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close menu")
                    }
                    .padding(.leading, destination.parent == nil ? 20 : 4)
                    .padding(.trailing, 8)
                    .padding(.top, max(proxy.safeAreaInsets.top, 8))
                    .padding(.bottom, 4)

                    drawerContent(bottomInset: proxy.safeAreaInsets.bottom)
                        .id(destination)
                }
                .frame(width: PageActionsDrawerPresentation.width(for: proxy.size.width))
                .frame(maxHeight: .infinity)
                .background(drawerBackground.ignoresSafeArea())
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(primaryText.opacity(0.08))
                        .frame(width: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: -8)
                .offset(x: max(0, dragOffset))
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .updating($dragOffset) { value, state, _ in
                            state = max(0, value.translation.width)
                        }
                        .onEnded { value in
                            if value.translation.width > 64 || value.predictedEndTranslation.width > 120 {
                                dismiss()
                            }
                        }
                )
            }
        }
        .preferredColorScheme(isPrivate && destination == .menu ? .dark : .light)
        .accessibilityAddTraits(.isModal)
    }

    private var drawerBackground: Color {
        isPrivate && destination == .menu ? .incognitoChrome : .browserCanvas
    }

    private var primaryText: Color {
        isPrivate && destination == .menu ? .white : .browserInk
    }

    private var secondaryText: Color {
        isPrivate && destination == .menu ? Color.white.opacity(0.62) : Color.secondary
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isPresented = false
        }
    }

    private func navigate(to destination: PageActionsDrawerDestination) {
        self.destination = destination
    }

    private func navigateBack() {
        guard let parent = destination.parent else { return }
        navigate(to: parent)
    }

    @ViewBuilder
    private func drawerContent(bottomInset: CGFloat) -> some View {
        switch destination {
        case .menu:
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    drawerSection(PageActionsDrawerMainSection.site.rawValue) {
                        drawerButton(
                            "Site Settings",
                            systemImage: "slider.horizontal.3",
                            enabled: canUsePageActions
                        ) {
                            navigate(to: .siteSettings)
                        }
                    }

                    drawerSection(PageActionsDrawerMainSection.page.rawValue) {
                        drawerButton(
                            isBookmarked ? "Unsave" : "Save",
                            systemImage: isBookmarked ? "bookmark.slash" : "bookmark",
                            enabled: canUsePageActions,
                            action: onToggleBookmark
                        )

                        drawerButton("Share", systemImage: "square.and.arrow.up", enabled: canUsePageActions, action: onShare)
                        drawerButton("Add Home Screen", systemImage: "square.and.arrow.down", enabled: canAddToHomeScreen, action: onAddToHomeScreen)
                    }

                    drawerSection(PageActionsDrawerMainSection.tab.rawValue) {
                        drawerButton(
                            "New Tab",
                            systemImage: "plus",
                            action: onNewTab
                        )
                        drawerButton(
                            "Tabs",
                            systemImage: "square.on.square",
                            action: onOpenTabs
                        )
                        drawerButton(
                            PageActionsDrawerTabPresentation.closeCurrentTabTitle,
                            systemImage: PageActionsDrawerTabPresentation.closeCurrentTabSystemImage,
                            enabled: !isPinned,
                            action: onCloseCurrentTab
                        )
                        drawerButton(
                            isPinned ? "Unpin Tab" : "Pin Tab",
                            systemImage: isPinned ? "pin.slash" : "pin",
                            enabled: canPin,
                            action: onTogglePinned
                        )
                        drawerButton(
                            BrowserMenuVisibilityPresentation.actionTitle(
                                menusAreMinimized: menusAreMinimized
                            ),
                            systemImage: BrowserMenuVisibilityPresentation.systemImage(
                                menusAreMinimized: menusAreMinimized
                            ),
                            enabled: canToggleMenus,
                            action: onToggleMenus
                        )
                        drawerButton("Tab Roles", assetImage: "RolesIcon") {
                            navigate(to: .tabRoles)
                        }
                    }

                    drawerSection(PageActionsDrawerMainSection.app.rawValue) {
                        drawerButton("Browsing Insights", systemImage: "chart.bar.xaxis", action: onOpenBrowsingInsights)
                        drawerButton("Library", systemImage: "books.vertical", action: onOpenLibrary)
                        drawerButton("Settings", systemImage: "gearshape") {
                            navigate(to: .browserSettings)
                        }
                        drawerButton("About", systemImage: "info.circle", action: onOpenAbout)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, max(bottomInset, 16))
            }
            .scrollIndicators(.hidden)

        case .siteSettings:
            DrawerSiteSettingsContent(
                page: page,
                linkOpeningPolicy: linkOpeningPolicy,
                onSetLinkOpeningPolicy: onSetLinkOpeningPolicy
            )

        case .tabRoles:
            DrawerTabRolesContent()
                .environmentObject(store)

        case .browserSettings:
            DrawerBrowserSettingsContent(
                onManageRoles: { navigate(to: .manageRoles) },
                onReplayOnboarding: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.18,
                        execute: onReplayOnboarding
                    )
                }
            )

        case .manageRoles:
            DrawerManageRolesContent()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func drawerSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(secondaryText)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

            content()
        }
    }

    private func drawerButton(
        _ title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            drawerLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func drawerButton(
        _ title: String,
        assetImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(assetImage)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)

                Text(title)
                    .font(.body.weight(.medium))

                Spacer(minLength: 0)
            }
            .foregroundStyle(primaryText)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: PageActionsDrawerPresentation.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func drawerLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20)

            Text(title)
                .font(.body.weight(.medium))

            Spacer(minLength: 0)
        }
        .foregroundStyle(primaryText)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: PageActionsDrawerPresentation.rowHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

enum PageActionsDrawerPresentation {
    static let maximumWidth: CGFloat = 336
    static let minimumOutsideMargin: CGFloat = 44
    static let rowHeight: CGFloat = 44
    static let submenuHorizontalPadding: CGFloat = 12
    static let submenuSectionSpacing: CGFloat = 12

    static func width(for containerWidth: CGFloat) -> CGFloat {
        min(maximumWidth, max(0, containerWidth - minimumOutsideMargin))
    }
}

enum PageActionsDrawerMainSection: String, CaseIterable {
    case site = "Site"
    case page = "Page"
    case tab = "Tab"
    case app = "App"
}

enum PageActionsDrawerTabPresentation {
    static let closeCurrentTabTitle = "Close current tab"
    static let closeCurrentTabSystemImage = "xmark"
}

private struct DrawerSubmenuSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

            content()

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
    }
}

private struct DrawerActionRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var assetImage: String?
    var showsChevron = false
    var isDestructive = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                drawerIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isDestructive ? Color.red : Color.browserInk)
            .padding(.horizontal, 12)
            .frame(
                maxWidth: .infinity,
                minHeight: subtitle == nil ? PageActionsDrawerPresentation.rowHeight : 52,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var drawerIcon: some View {
        if let assetImage {
            Image(assetImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .frame(width: 20)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20)
        } else {
            Color.clear.frame(width: 20, height: 20)
        }
    }
}

private struct DrawerInfoRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var assetImage: String?

    var body: some View {
        HStack(spacing: 12) {
            drawerIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.browserInk)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(
            maxWidth: .infinity,
            minHeight: subtitle == nil ? PageActionsDrawerPresentation.rowHeight : 52,
            alignment: .leading
        )
    }

    @ViewBuilder
    private var drawerIcon: some View {
        if let assetImage {
            Image(assetImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.browserInk)
                .frame(width: 19, height: 19)
                .frame(width: 20)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.browserInk)
                .frame(width: 20)
        } else {
            Color.clear.frame(width: 20, height: 20)
        }
    }
}

private struct DrawerToggleRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.browserInk)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.browserInk)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.browserAccent)
        }
        .padding(.horizontal, 12)
        .frame(
            maxWidth: .infinity,
            minHeight: subtitle == nil ? PageActionsDrawerPresentation.rowHeight : 52,
            alignment: .leading
        )
    }
}

private struct DrawerSiteSettingsContent: View {
    @ObservedObject var page: WebPage
    let linkOpeningPolicy: BrowserLinkOpeningPolicy
    let onSetLinkOpeningPolicy: (BrowserLinkOpeningPolicy) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageActionsDrawerPresentation.submenuSectionSpacing) {
                DrawerSubmenuSection("Current Site") {
                    DrawerInfoRow(
                        title: siteName,
                        systemImage: "globe"
                    )
                }

                DrawerSubmenuSection(
                    "External Links",
                    footer: "Choose how deliberate link taps leaving this site open. Links within this site keep the website's normal behavior."
                ) {
                    Menu {
                        ForEach(BrowserLinkOpeningPolicy.allCases) { policy in
                            Button {
                                onSetLinkOpeningPolicy(policy)
                            } label: {
                                if policy == linkOpeningPolicy {
                                    Label(policy.title, systemImage: "checkmark")
                                } else {
                                    Text(policy.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: linkOpeningPolicy.systemImage)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.browserInk)
                                .frame(width: 20)

                            Text(linkOpeningPolicy.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Color.browserInk)

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: PageActionsDrawerPresentation.rowHeight,
                            alignment: .leading
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let support = page.siteAccessibilitySupport,
                   support.supportsBottomNavigation {
                    DrawerSubmenuSection(
                        "Accessibility",
                        footer: "Adds a compact one-thumb footer for \(support.displayName) while leaving the original page navigation unchanged."
                    ) {
                        DrawerToggleRow(
                            title: "Bottom navigation",
                            systemImage: "hand.tap",
                            isOn: Binding(
                                get: { page.usesSiteBottomNavigation },
                                set: { enabled in
                                    Task { await page.setSiteBottomNavigationEnabled(enabled) }
                                }
                            )
                        )
                    }
                } else {
                    DrawerSubmenuSection("Accessibility") {
                        DrawerInfoRow(
                            title: "No adjustments available",
                            systemImage: "accessibility"
                        )
                    }
                }

                DrawerSubmenuSection(
                    "App Promos",
                    footer: "Control app promotions for this site and remembered choices for opening installed apps."
                ) {
                    DrawerAppPromosRows(
                        page: page,
                        preferences: page.externalAppLinkPreferences
                    )
                }
            }
            .padding(.horizontal, PageActionsDrawerPresentation.submenuHorizontalPadding)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private var siteName: String {
        AppPromptPreferences.normalizedHost(from: page.url) ?? "Current Site"
    }
}

private struct DrawerAppPromosRows: View {
    @ObservedObject var page: WebPage
    @ObservedObject var preferences: ExternalAppLinkPreferences

    var body: some View {
        if page.url?.host != nil {
            DrawerToggleRow(
                title: "Hide app promos",
                systemImage: "app.badge",
                isOn: Binding(
                    get: { page.blocksAppPrompts },
                    set: { blocked in
                        Task { await page.setAppPromptBlocking(blocked) }
                    }
                )
            )
        }

        if !preferences.records.isEmpty {
            ForEach(preferences.records) { record in
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.browserInk)
                        .frame(width: 20)

                    Text(record.serviceName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.browserInk)

                    Spacer(minLength: 8)

                    Menu {
                        ForEach(ExternalAppLinkChoice.allCases) { choice in
                            Button {
                                preferences.setChoice(choice, for: record.serviceKey)
                            } label: {
                                if choice == record.choice {
                                    Label(choice.title, systemImage: "checkmark")
                                } else {
                                    Text(choice.title)
                                }
                            }
                        }

                        Divider()

                        Button("Ask Next Time") {
                            preferences.removeChoice(for: record.serviceKey)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(record.choice.title)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.browserAccent)
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: PageActionsDrawerPresentation.rowHeight)
            }
        }

        if !preferences.records.isEmpty {
            DrawerActionRow(
                title: "Ask again for all",
                systemImage: "arrow.counterclockwise",
                isDestructive: true,
                action: preferences.resetAll
            )
        }
    }
}

private struct DrawerBrowserSettingsContent: View {
    let onManageRoles: () -> Void
    let onReplayOnboarding: () -> Void

    @ObservedObject private var passkeySupport = BrowserPasskeySupport.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageActionsDrawerPresentation.submenuSectionSpacing) {
                DrawerSubmenuSection("Organization") {
                    DrawerActionRow(
                        title: "Manage Roles",
                        assetImage: "RolesIcon",
                        showsChevron: true,
                        action: onManageRoles
                    )
                }

                DrawerSubmenuSection("Security") {
                    if passkeySupport.authorizationStatus == .disabled {
                        DrawerInfoRow(
                            title: BrowserCapabilityPresentation.passkeyTitle,
                            subtitle: BrowserCapabilityPresentation.passkeyDisabledStatus,
                            systemImage: "key.fill"
                        )

                        Text(BrowserCapabilityPresentation.passkeySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                    } else if passkeySupport.authorizationStatus == .authorized {
                        DrawerInfoRow(
                            title: BrowserCapabilityPresentation.passkeyTitle,
                            subtitle: passkeySupport.statusDescription,
                            systemImage: "key.fill"
                        )
                    } else {
                        DrawerActionRow(
                            title: BrowserCapabilityPresentation.passkeyTitle,
                            subtitle: passkeySupport.statusDescription,
                            systemImage: "key.fill"
                        ) {
                            if passkeySupport.authorizationStatus == .denied {
                                passkeySupport.openSettings()
                            } else {
                                passkeySupport.requestAuthorization()
                            }
                        }
                    }
                }

                DrawerSubmenuSection("Help") {
                    DrawerActionRow(
                        title: "Replay Onboarding",
                        systemImage: "rectangle.stack.badge.play",
                        action: onReplayOnboarding
                    )
                }
            }
            .padding(.horizontal, PageActionsDrawerPresentation.submenuHorizontalPadding)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            passkeySupport.refreshAuthorizationStatus()
        }
    }
}

private struct DrawerManageRolesContent: View {
    @EnvironmentObject private var store: BrowserStore

    @State private var newRoleName = ""
    @State private var roleToRename: BrowserRole?
    @State private var renamedRoleName = ""
    @State private var validationMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageActionsDrawerPresentation.submenuSectionSpacing) {
                DrawerSubmenuSection(
                    "Your Roles",
                    footer: "Roles add context to the same person. Archiving removes a Role from tabs and selectors without deleting it."
                ) {
                    if store.activeRoles.isEmpty {
                        DrawerInfoRow(
                            title: "No Roles yet",
                            subtitle: "Add only the contexts that are useful to you.",
                            assetImage: "RolesIcon"
                        )
                    } else {
                        ForEach(store.rolesByUsage()) { role in
                            roleRow(role)
                        }
                    }
                }

                DrawerSubmenuSection("Add Role") {
                    HStack(spacing: 12) {
                        Image("RolesIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.browserInk)
                            .frame(width: 19, height: 19)
                            .frame(width: 20)

                        TextField("Role name", text: $newRoleName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(addRole)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: PageActionsDrawerPresentation.rowHeight)

                    DrawerActionRow(
                        title: "Add Role",
                        systemImage: "plus",
                        enabled: !newRoleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: addRole
                    )

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                    }
                }

                if !store.archivedRoles.isEmpty {
                    DrawerSubmenuSection("Archived") {
                        ForEach(store.archivedRoles) { role in
                            HStack(spacing: 12) {
                                Image("RolesIcon")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 19, height: 19)
                                    .frame(width: 20)

                                Text(role.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Spacer(minLength: 8)

                                Button("Restore") {
                                    store.setRoleArchived(role.id, archived: false)
                                }
                                .buttonStyle(.plain)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.browserAccent)
                                .frame(minHeight: 44)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: PageActionsDrawerPresentation.rowHeight)
                        }
                    }
                }
            }
            .padding(.horizontal, PageActionsDrawerPresentation.submenuHorizontalPadding)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .alert("Rename Role", isPresented: renameAlertPresented) {
            TextField("Role name", text: $renamedRoleName)
            Button("Cancel", role: .cancel) {
                roleToRename = nil
                renamedRoleName = ""
            }
            Button("Rename", action: renameRole)
                .disabled(renamedRoleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The updated name appears everywhere this Role is used.")
        }
    }

    private func roleRow(_ role: BrowserRole) -> some View {
        HStack(spacing: 12) {
            Image("RolesIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.browserInk)
                .frame(width: 19, height: 19)
                .frame(width: 20)

            Text(role.name)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.browserInk)

            Spacer(minLength: 8)

            Menu {
                Button {
                    roleToRename = role
                    renamedRoleName = role.name
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    store.setRoleArchived(role.id, archived: true)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.vertical")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.browserControl)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(role.name)")
        }
        .padding(.leading, 12)
        .frame(minHeight: PageActionsDrawerPresentation.rowHeight)
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { roleToRename != nil },
            set: { presented in
                if !presented {
                    roleToRename = nil
                    renamedRoleName = ""
                }
            }
        )
    }

    private func addRole() {
        guard store.addRole(name: newRoleName) != nil else {
            validationMessage = "Use a unique Role name."
            return
        }
        newRoleName = ""
        validationMessage = nil
    }

    private func renameRole() {
        guard let roleToRename else { return }
        validationMessage = store.renameRole(roleToRename.id, name: renamedRoleName)
            ? nil
            : "Use a unique Role name."
        self.roleToRename = nil
        renamedRoleName = ""
    }
}

private struct URLShareActivityView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum BrowserChromeLayout {
    static let expandedHeaderHeight: CGFloat = 62
    static let collapsedHeaderHeight: CGFloat = 0
    static let footerControlHeight: CGFloat = 52

    static func footerHeight(safeAreaBottom: CGFloat) -> CGFloat {
        footerControlHeight + max(safeAreaBottom, 0)
    }
}

enum FacebookAccessibilityFooterLayout {
    static func bottomPadding(
        safeAreaBottom: CGFloat,
        browserToolbarHeight: CGFloat
    ) -> CGFloat {
        max(max(safeAreaBottom, 0) - max(browserToolbarHeight, 0), 0)
    }
}

enum MinimizedControlSide: String, Equatable {
    case leading
    case trailing

    var alignment: Alignment {
        self == .leading ? .bottomLeading : .bottomTrailing
    }
}

enum MinimizedControlPlacement {
    static let horizontalInset: CGFloat = 16
    static let switchThreshold: CGFloat = 44

    static func constrainedTranslation(
        _ translation: CGFloat,
        currentSide: MinimizedControlSide,
        containerWidth: CGFloat
    ) -> CGFloat {
        let maximumTravel = max(0, containerWidth - 84)
        switch currentSide {
        case .leading:
            return min(max(0, translation), maximumTravel)
        case .trailing:
            return max(min(0, translation), -maximumTravel)
        }
    }

    static func resolvedSide(
        currentSide: MinimizedControlSide,
        translation: CGFloat,
        predictedEndTranslation: CGFloat
    ) -> MinimizedControlSide {
        let committedTranslation = abs(predictedEndTranslation) > abs(translation)
            ? predictedEndTranslation
            : translation

        switch currentSide {
        case .leading:
            return committedTranslation >= switchThreshold ? .trailing : .leading
        case .trailing:
            return committedTranslation <= -switchThreshold ? .leading : .trailing
        }
    }
}

enum PagePresentationMode {
    case web
    case reader

    var showsBrowserChrome: Bool {
        self == .web
    }

    var showsReaderActions: Bool {
        self == .reader
    }
}

@MainActor
final class ReaderActionVisibilityModel: ObservableObject {
    @Published private(set) var isVisible = true

    private var lastOffset: CGFloat?

    func update(offset: CGFloat) {
        let normalizedOffset = max(0, offset)

        if normalizedOffset <= 4 {
            isVisible = true
            lastOffset = normalizedOffset
            return
        }

        guard let lastOffset else {
            self.lastOffset = normalizedOffset
            return
        }

        let delta = normalizedOffset - lastOffset
        if delta > 2 {
            isVisible = false
        } else if delta < -2 {
            isVisible = true
        }

        self.lastOffset = normalizedOffset
    }

    func updateDrag(translationHeight: CGFloat) {
        if translationHeight < -4 {
            isVisible = false
        } else if translationHeight > 4 {
            isVisible = true
        }
    }

    func reset() {
        isVisible = true
        lastOffset = nil
    }
}

struct InlineReaderSurface: View {
    let document: ReaderDocument
    let onScrollOffsetChange: (CGFloat) -> Void
    let onDragTranslationChange: (CGFloat) -> Void

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: ReaderScrollOffsetPreferenceKey.self,
                        value: -proxy.frame(in: .named("inline-reader-scroll")).minY
                    )
            }
            .frame(height: 0)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.title)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(Color.browserInk)

                    HStack(spacing: 8) {
                        Text(document.siteName ?? document.sourceURL.host ?? "Source")
                        if let author = document.author {
                            Text("•")
                            Text(author)
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if document.captureKind == .referenceOnly {
                        Label("Reference-only capture", systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                ReaderHeroImage(url: document.previewImageURL)

                Divider()

                Text(document.text)
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(Color.browserInk)
                    .lineSpacing(7)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 112)
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "inline-reader-scroll")
        .onPreferenceChange(ReaderScrollOffsetPreferenceKey.self, perform: onScrollOffsetChange)
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { onDragTranslationChange($0.translation.height) }
        )
        .background(Color.readerCanvas)
    }
}

struct ReaderScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ReadingListFeedback: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

private struct DrawerTabRolesContent: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PageActionsDrawerPresentation.submenuSectionSpacing) {
                DrawerSubmenuSection("Current Selection") {
                    DrawerInfoRow(
                        title: selectionSummary,
                        assetImage: "RolesIcon"
                    )
                }

                DrawerSubmenuSection(
                    "Available Roles",
                    footer: "Roles are optional context labels for this tab. Selecting none leaves it unlabeled."
                ) {
                    if store.activeRoles.isEmpty {
                        DrawerInfoRow(
                            title: "No Roles yet",
                            subtitle: "Add or restore Roles from Settings.",
                            assetImage: "RolesIcon"
                        )
                    } else {
                        ForEach(store.rolesByUsage(prioritizing: selectedRoleIDs)) { role in
                            roleSelectionRow(role)
                        }
                    }
                }
            }
            .padding(.horizontal, PageActionsDrawerPresentation.submenuHorizontalPadding)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func roleSelectionRow(_ role: BrowserRole) -> some View {
        let isSelected = selectedRoleIDs.contains(role.id)

        return Button {
            store.toggleSelectedTabRole(role.id)
        } label: {
            HStack(spacing: 12) {
                Image("RolesIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 19, height: 19)
                    .frame(width: 20)
                    .foregroundStyle(Color.browserInk)

                Text(role.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.browserInk)

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? Color.browserAccent : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: PageActionsDrawerPresentation.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var selectedRoleIDs: Set<UUID> {
        Set(store.selectedTab?.roleIDs ?? [])
    }

    private var selectionSummary: String {
        let names = store.activeRoles
            .filter { selectedRoleIDs.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? "No Role selected" : names.joined(separator: ", ")
    }
}

private struct PinnedTabQuickSwitcherView: View {
    @EnvironmentObject private var store: BrowserStore
    let currentTabID: UUID
    let canSave: Bool
    let isSaved: Bool
    let menusAreMinimized: Bool
    let onSelect: (UUID) -> Void
    let onSave: () -> Void
    let onNewTab: () -> Void
    let onOpenSubtab: () -> Void
    let onOpenTabs: () -> Void
    let onToggleMenus: () -> Void
    let onOpenMainMenu: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(PinnedTabQuickSwitcherPresentation.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.browserInk)

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.browserInk)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Pinned Tabs")
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 8)

            ScrollView {
                VStack(spacing: PinnedTabQuickSwitcherPresentation.rowSpacing) {
                    if store.pinnedTabs.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "pin")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(Color.secondary)
                            Text("No Pinned Tabs")
                                .font(.subheadline.weight(.semibold))
                            Text("Pin a tab from its page menu or tab card.")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: PinnedTabQuickSwitcherPresentation.itemHeight)
                    } else {
                        ForEach(
                            Array(
                                PinnedTabQuickSwitcherPresentation.rows(
                                    items: store.pinnedTabs
                                ).enumerated()
                            ),
                            id: \.offset
                        ) { _, row in
                            HStack(spacing: PinnedTabQuickSwitcherPresentation.horizontalSpacing) {
                                ForEach(row) { pinnedTab in
                                    pinnedTabAppIcon(pinnedTab)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, PinnedTabQuickSwitcherPresentation.verticalPadding)
            }
            .defaultScrollAnchor(.bottom)

            Divider()

            bottomActions
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .background(Color.browserCanvas)
    }

    private func pinnedTabAppIcon(_ tab: BrowserTab) -> some View {
        Button {
            onSelect(tab.id)
        } label: {
            VStack(spacing: 7) {
                PinnedTabIconArtwork(
                    tab: tab,
                    isSelected: tab.id == currentTabID
                )

                Text(PinnedTabQuickSwitcherPresentation.displayName(for: tab.url))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.browserInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity)
            }
            .frame(
                width: PinnedTabQuickSwitcherPresentation.itemWidth,
                height: PinnedTabQuickSwitcherPresentation.itemHeight,
                alignment: .top
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(PinnedTabQuickSwitcherPresentation.displayName(for: tab.url))")
        .accessibilityValue(tab.id == currentTabID ? "Current tab" : "Pinned tab")
    }

    private var bottomActions: some View {
        HStack {
            ForEach(
                Array(PinnedTabQuickSwitcherPresentation.actionOrder.enumerated()),
                id: \.element
            ) { index, action in
                if index > 0 { Spacer() }
                quickAction(action)
            }
        }
        .frame(minHeight: PinnedTabQuickSwitcherPresentation.actionBarHeight)
    }

    @ViewBuilder
    private func quickAction(_ action: PinnedTabQuickSwitcherAction) -> some View {
        switch action {
        case .menuVisibility:
            iconAction(
                BrowserMenuVisibilityPresentation.actionTitle(
                    menusAreMinimized: menusAreMinimized
                ),
                systemImage: BrowserMenuVisibilityPresentation.systemImage(
                    menusAreMinimized: menusAreMinimized
                ),
                action: onToggleMenus
            )
        case .save:
            iconAction(
                PinnedTabQuickSwitcherPresentation.saveTitle(isSaved: isSaved),
                systemImage: PinnedTabQuickSwitcherPresentation.saveSystemImage(isSaved: isSaved),
                disabled: !canSave,
                action: onSave
            )
        case .newTab:
            iconAction(
                PinnedTabQuickSwitcherPresentation.newTabTitle,
                systemImage: "plus",
                action: onNewTab
            )
        case .subtab:
            iconAction(
                PinnedTabQuickSwitcherPresentation.subtabTitle,
                systemImage: PinnedTabQuickSwitcherPresentation.subtabSystemImage,
                action: onOpenSubtab
            )
        case .tabs:
            iconAction(
                "Tabs",
                systemImage: "square.on.square",
                action: onOpenTabs
            )
        case .mainMenu:
            iconAction(
                PinnedTabQuickSwitcherPresentation.mainMenuTitle,
                systemImage: PinnedTabQuickSwitcherPresentation.mainMenuSystemImage,
                rotationDegrees: PinnedTabQuickSwitcherPresentation.mainMenuRotationDegrees,
                action: onOpenMainMenu
            )
        }
    }

    private func iconAction(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        rotationDegrees: Double = 0,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .rotationEffect(.degrees(rotationDegrees))
                .foregroundStyle(Color.browserInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(title)
    }

}

struct PinnedTabIconArtwork: View {
    let tab: BrowserTab
    var isSelected = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)

            if let url = tab.faviconURL ?? URLResolver.conventionalFaviconURL(for: tab.url) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 60, height: 60)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.browserInk.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: PinnedTabQuickSwitcherPresentation.selectedIndicatorSystemImage)
                    .font(.system(size: 19, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.browserAccent)
                    .background(Color.white, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
        .shadow(color: Color.browserInk.opacity(0.12), radius: 8, y: 3)
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .font(.system(size: 25, weight: .medium))
            .foregroundStyle(Color.browserAccent)
    }
}

enum PinnedTabQuickSwitcherAction: String, CaseIterable {
    case menuVisibility
    case save
    case newTab
    case subtab
    case tabs
    case mainMenu
}

enum PinnedTabQuickSwitcherPresentation {
    static let title = "Pinned Tabs"
    static let newTabTitle = "New Tab"
    static let subtabTitle = "Open Subtab"
    static let subtabSystemImage = "macwindow.on.rectangle"
    static let columnCount = 4
    static let itemWidth: CGFloat = 72
    static let horizontalSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 16
    static let itemHeight: CGFloat = 92
    static let verticalPadding: CGFloat = 20
    static let actionBarHeight: CGFloat = 52
    static let sheetChromeHeight: CGFloat = 196
    static let maximumSheetHeight: CGFloat = 640
    static let selectedIndicatorSystemImage = "checkmark.circle.fill"
    static let mainMenuTitle = "Main Menu"
    static let mainMenuSystemImage = "ellipsis"
    static let mainMenuRotationDegrees = 90.0
    static let actionOrder: [PinnedTabQuickSwitcherAction] = [
        .menuVisibility,
        .save,
        .newTab,
        .subtab,
        .tabs,
        .mainMenu
    ]

    static func saveTitle(isSaved: Bool) -> String {
        isSaved ? "Saved" : "Save"
    }

    static func saveSystemImage(isSaved: Bool) -> String {
        isSaved ? "bookmark.fill" : "bookmark"
    }

    static func rows<Item>(items: [Item]) -> [[Item]] {
        Array(
            stride(from: 0, to: items.count, by: columnCount).map { start in
                Array(items[start..<min(start + columnCount, items.count)])
            }.reversed()
        )
    }

    static func sheetHeight(itemCount: Int) -> CGFloat {
        let rowCount = max(1, (max(0, itemCount) + columnCount - 1) / columnCount)
        let rowsHeight = CGFloat(rowCount) * itemHeight
            + CGFloat(max(0, rowCount - 1)) * rowSpacing
        return min(maximumSheetHeight, sheetChromeHeight + rowsHeight)
    }

    static func displayName(for url: URL?) -> String {
        guard var host = url?.host?.lowercased(), !host.isEmpty else { return "New Tab" }
        while let prefix = ["www.", "m.", "mobile."].first(where: { host.hasPrefix($0) }) {
            host.removeFirst(prefix.count)
        }

        let labels = host.split(separator: ".").map(String.init)
        guard !labels.isEmpty else { return "New Tab" }

        let baseIndex: Int
        if labels.count >= 3,
           labels.last?.count == 2,
           ["ac", "co", "com", "edu", "gov", "net", "org"].contains(labels[labels.count - 2]) {
            baseIndex = labels.count - 3
        } else if labels.count >= 2 {
            baseIndex = labels.count - 2
        } else {
            baseIndex = 0
        }

        let words = labels[baseIndex]
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        return words.isEmpty ? "New Tab" : words.joined(separator: " ")
    }
}

enum BrowserMenuVisibilityPresentation {
    static func actionTitle(menusAreMinimized: Bool) -> String {
        menusAreMinimized ? "Show Menus" : "Minimize Menus"
    }

    static func systemImage(menusAreMinimized: Bool) -> String {
        menusAreMinimized ? "rectangle.expand.vertical" : "rectangle.compress.vertical"
    }
}

enum BrowserInitialFocusPolicy {
    static func shouldFocusBlankTab(
        isBlankTab: Bool,
        onboardingIsPresented: Bool,
        browserSurfaceIsObscured: Bool
    ) -> Bool {
        isBlankTab && !onboardingIsPresented && !browserSurfaceIsObscured
    }
}

private struct NewTabView: View {
    @Binding var address: String
    @Binding var addressFocused: Bool
    let isIncognito: Bool
    let onSubmit: () -> Void
    let onDismissKeyboard: () -> Void
    let onToggleIncognito: () -> Void

    var body: some View {
        ZStack {
            (isIncognito ? Color.incognitoCanvas : Color.browserCanvas)
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissKeyboard)

            VStack(spacing: 28) {
                brandIdentity
                centralAddressField
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .offset(y: -24)
        }
        .accessibilityElement(children: .contain)
    }

    private var brandIdentity: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 68, weight: .regular))
                .foregroundStyle(isIncognito ? Color.white : Color.browserInk)
                .frame(width: 88, height: 88)
            .accessibilityHidden(true)

            Text(isIncognito ? "Incognito Browser" : "Personal Browser")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(isIncognito ? Color.white : Color.browserInk)

            Text(
                isIncognito
                    ? "Pages and tabs from this session are not retained."
                    : "One browser. Your Roles add context."
            )
            .font(.title3)
            .foregroundStyle(isIncognito ? Color.white.opacity(0.68) : Color.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var centralAddressField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isIncognito ? Color.white.opacity(0.72) : Color.secondary)
                .frame(width: 28, height: 44)

            AddressBarTextField(
                text: $address,
                isFocused: $addressFocused,
                inactiveText: "",
                textColor: isIncognito ? .white : UIColor(Color.browserInk),
                tintColor: isIncognito ? .white : UIColor(Color.browserAccent),
                onSubmit: onSubmit,
                placeholder: AddressBarPresentation.newTabPlaceholder,
                fontSize: 17
            )
            .frame(height: 44)

            if !address.isEmpty {
                Button(action: clearAddress) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isIncognito ? Color.white.opacity(0.62) : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear address")
            }

            Button(action: onToggleIncognito) {
                Image(systemName: isIncognito ? "eye.slash.fill" : "eye.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isIncognito ? Color.white : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isIncognito ? "Use normal browsing" : "Start Incognito")

            if addressFocused {
                Button(action: dismissKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isIncognito ? Color.white.opacity(0.72) : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(
            isIncognito ? Color.incognitoSurface : Color.browserAddressField,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isIncognito
                        ? Color.white.opacity(addressFocused ? 0.34 : 0.12)
                        : Color.browserAccent.opacity(addressFocused ? 0.42 : 0.12),
                    lineWidth: 1.25
                )
        }
        .shadow(color: Color.browserInk.opacity(0.08), radius: 14, y: 5)
        .onTapGesture {
            addressFocused = true
        }
        .accessibilityLabel(AddressBarPresentation.newTabPlaceholder)
    }

    private func clearAddress() {
        address = ""
        addressFocused = true
    }

    private func dismissKeyboard() {
        addressFocused = false
        onDismissKeyboard()
    }
}
