import XCTest
@testable import PersonalBrowser

@MainActor
final class ChromeBarsModelTests: XCTestCase {
    func testFirstUseOnboardingSuppressesBlankTabKeyboardFocus() {
        XCTAssertFalse(
            BrowserInitialFocusPolicy.shouldFocusBlankTab(
                isBlankTab: true,
                onboardingIsPresented: true,
                browserSurfaceIsObscured: false
            )
        )
        XCTAssertTrue(
            BrowserInitialFocusPolicy.shouldFocusBlankTab(
                isBlankTab: true,
                onboardingIsPresented: false,
                browserSurfaceIsObscured: false
            )
        )
        XCTAssertFalse(
            BrowserInitialFocusPolicy.shouldFocusBlankTab(
                isBlankTab: false,
                onboardingIsPresented: false,
                browserSurfaceIsObscured: false
            )
        )
        XCTAssertFalse(
            BrowserInitialFocusPolicy.shouldFocusBlankTab(
                isBlankTab: true,
                onboardingIsPresented: false,
                browserSurfaceIsObscured: true
            )
        )
    }

    func testFullScreenLibraryIsTreatedAsObscuringBrowserSurface() {
        XCTAssertTrue(
            BrowserRootSurfacePolicy.isBrowserSurfaceObscured(
                showingLibrary: true,
                showingInsights: false,
                showingAbout: false,
                showingOnboarding: false,
                showingMediaPlayer: false,
                showingPDF: false
            )
        )
    }

    func testFullScreenAboutHidesUnderlyingBrowserFromInteractionAndAccessibility() {
        XCTAssertFalse(
            BrowserRootSurfacePolicy.exposesUnderlyingBrowser(
                showingLibrary: false,
                showingInsights: false,
                showingAbout: true,
                showingOnboarding: false,
                showingMediaPlayer: false,
                showingPDF: false
            )
        )
        XCTAssertTrue(
            BrowserRootSurfacePolicy.exposesUnderlyingBrowser(
                showingLibrary: false,
                showingInsights: false,
                showingAbout: false,
                showingOnboarding: false,
                showingMediaPlayer: false,
                showingPDF: false
            )
        )
    }

    func testAboutDescribesIndependentOpenSourceSnapshot() {
        XCTAssertEqual(BrowserAboutPresentation.productName, "Personal Browser")
        XCTAssertTrue(BrowserAboutPresentation.snapshotStatus.contains("MIT-licensed"))
        XCTAssertTrue(BrowserAboutPresentation.snapshotSummary.contains("periodic"))
        XCTAssertTrue(BrowserAboutPresentation.snapshotSummary.contains("independently"))
        XCTAssertTrue(BrowserAboutPresentation.privacySummary.contains("app's own sandbox"))
        XCTAssertEqual(BrowserAboutPresentation.commercialProductName, "Browser by Prifina")
        XCTAssertEqual(BrowserAboutPresentation.commercialWebsiteURL.host, "browser.prifina.com")
        XCTAssertTrue(BrowserAboutPresentation.commercialSummary.contains("maintained"))
        XCTAssertTrue(BrowserCapabilityPresentation.sourceBuildSummary.contains("Apple-managed"))
        XCTAssertTrue(BrowserCapabilityPresentation.defaultBrowserSummary.contains("Not included"))
        XCTAssertTrue(BrowserCapabilityPresentation.passkeySummary.contains("separately configured"))
        XCTAssertTrue(BrowserCapabilityPresentation.addToHomeScreenSummary.contains("source build"))
    }

    func testCollapsedChromeLeavesNoHeaderOrFooterRemainder() {
        XCTAssertEqual(BrowserChromeLayout.collapsedHeaderHeight, 0)
        XCTAssertEqual(BrowserChromeLayout.footerHeight(safeAreaBottom: 34) * 0, 0)
    }

    func testFooterReservesControlAndSafeAreaHeightWhileVisible() {
        XCTAssertEqual(BrowserChromeLayout.footerControlHeight, 52)
        XCTAssertEqual(BrowserChromeLayout.footerHeight(safeAreaBottom: 34), 86)
        XCTAssertEqual(BrowserChromeLayout.footerHeight(safeAreaBottom: -4), 52)
    }

    func testFacebookFooterClearsHomeIndicatorWhenBrowserToolbarIsHidden() {
        XCTAssertEqual(
            FacebookAccessibilityFooterLayout.bottomPadding(
                safeAreaBottom: 34,
                browserToolbarHeight: 0
            ),
            34
        )
        XCTAssertEqual(
            FacebookAccessibilityFooterLayout.bottomPadding(
                safeAreaBottom: 34,
                browserToolbarHeight: 86
            ),
            0
        )
        XCTAssertEqual(
            FacebookAccessibilityFooterLayout.bottomPadding(
                safeAreaBottom: 34,
                browserToolbarHeight: 18
            ),
            16
        )
    }

    func testDownwardScrollCollapsesBarsContinuously() {
        let model = ChromeBarsModel()
        model.beginScroll(offset: 0, contentHeight: 2_000, viewportHeight: 700)
        model.updateScroll(offset: 27, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.001)
    }

    func testDirectionReversalImmediatelyExpandsBars() {
        let model = ChromeBarsModel()
        model.beginScroll(offset: 0, contentHeight: 2_000, viewportHeight: 700)
        model.updateScroll(offset: 54, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        model.updateScroll(offset: 27, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        XCTAssertEqual(model.progress, 0.5, accuracy: 0.001)
    }

    func testScrollEndSettlesAtHalfwayThreshold() {
        let mostlyVisible = ChromeBarsModel()
        mostlyVisible.beginScroll(offset: 0, contentHeight: 2_000, viewportHeight: 700)
        mostlyVisible.updateScroll(offset: 26, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        mostlyVisible.endScroll()
        XCTAssertEqual(mostlyVisible.progress, 1)

        let mostlyHidden = ChromeBarsModel()
        mostlyHidden.beginScroll(offset: 0, contentHeight: 2_000, viewportHeight: 700)
        mostlyHidden.updateScroll(offset: 28, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        mostlyHidden.endScroll()
        XCTAssertEqual(mostlyHidden.progress, 0)
    }

    func testShortContentDoesNotCollapse() {
        let model = ChromeBarsModel()
        model.beginScroll(offset: 0, contentHeight: 720, viewportHeight: 700)
        model.updateScroll(offset: 100, contentHeight: 720, viewportHeight: 700, isZooming: false)
        XCTAssertEqual(model.progress, 1)
    }

    func testTopOfPageShowsBars() {
        let model = ChromeBarsModel()
        model.beginScroll(offset: 0, contentHeight: 2_000, viewportHeight: 700)
        model.updateScroll(offset: 54, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        model.updateScroll(offset: 0, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        XCTAssertEqual(model.progress, 1)
    }

    func testWebPageRepublishesChromeProgressForSwiftUI() {
        let tab = BrowserTab(identityID: UUID())
        let page = WebPage(tab: tab)

        page.chromeBars.beginScroll(offset: 0, contentHeight: 2_000, viewportHeight: 700)
        page.chromeBars.updateScroll(offset: 27, contentHeight: 2_000, viewportHeight: 700, isZooming: false)

        XCTAssertEqual(page.chromeProgress, 0.5, accuracy: 0.001)
    }

    func testViewportResizeAtBottomDoesNotOscillateProgress() {
        let model = ChromeBarsModel()
        model.beginScroll(offset: 1_200, contentHeight: 2_000, viewportHeight: 700)
        model.updateScroll(offset: 1_225, contentHeight: 2_000, viewportHeight: 700, isZooming: false)
        let progressBeforeResize = model.progress

        // The bars collapsing grows the viewport and UIKit adjusts the offset
        // to keep the page bottom pinned. This is not a new user scroll.
        model.updateScroll(offset: 1_200, contentHeight: 2_000, viewportHeight: 800, isZooming: false)

        XCTAssertEqual(model.progress, progressBeforeResize, accuracy: 0.001)
    }

    func testPinnedHiddenIgnoresScrollAndShowUntilExplicitReveal() {
        let model = ChromeBarsModel()
        model.hideUntilRevealed(animated: false)

        model.show(animated: false)
        model.beginScroll(offset: 100, contentHeight: 2_000, viewportHeight: 700)
        model.updateScroll(offset: 50, contentHeight: 2_000, viewportHeight: 700, isZooming: false)

        XCTAssertTrue(model.isPinnedHidden)
        XCTAssertEqual(model.progress, 0)

        model.reveal(animated: false)
        XCTAssertFalse(model.isPinnedHidden)
        XCTAssertEqual(model.progress, 1)
    }

    func testHiddenControlsStateIsIndependentPerTabPage() {
        let first = WebPage(tab: BrowserTab(identityID: UUID()))
        let second = WebPage(tab: BrowserTab(identityID: UUID()))

        first.hideBrowserControls()

        XCTAssertTrue(first.browserControlsPinnedHidden)
        XCTAssertEqual(first.chromeProgress, 0)
        XCTAssertFalse(second.browserControlsPinnedHidden)
        XCTAssertEqual(second.chromeProgress, 1)
    }

    func testTwoFingerActionRequestsQuickSwitcherOnlyWhileControlsAreHidden() {
        let page = WebPage(tab: BrowserTab(identityID: UUID(), browserControlsHidden: true))
        var requestCount = 0
        page.onQuickSwitcherRequested = { requestCount += 1 }

        XCTAssertTrue(page.requestQuickSwitcherIfControlsHidden())

        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(page.browserControlsPinnedHidden)

        page.revealBrowserControls()

        XCTAssertFalse(page.requestQuickSwitcherIfControlsHidden())
        XCTAssertEqual(requestCount, 1)
    }

    func testRightEdgeQuickSwitcherGestureOnlyBeginsForHiddenHorizontalInwardSwipe() {
        XCTAssertTrue(
            QuickSwitcherEdgeSwipePolicy.canBegin(
                controlsHidden: true,
                velocity: CGPoint(x: -500, y: 40)
            )
        )
        XCTAssertFalse(
            QuickSwitcherEdgeSwipePolicy.canBegin(
                controlsHidden: false,
                velocity: CGPoint(x: -500, y: 40)
            )
        )
        XCTAssertFalse(
            QuickSwitcherEdgeSwipePolicy.canBegin(
                controlsHidden: true,
                velocity: CGPoint(x: -80, y: 300)
            )
        )
        XCTAssertFalse(
            QuickSwitcherEdgeSwipePolicy.canBegin(
                controlsHidden: true,
                velocity: CGPoint(x: 500, y: 20)
            )
        )
    }

    func testRightEdgeQuickSwitcherGestureRequiresCommittedHorizontalTravel() {
        XCTAssertTrue(
            QuickSwitcherEdgeSwipePolicy.shouldOpen(
                translation: CGPoint(x: -72, y: 12)
            )
        )
        XCTAssertFalse(
            QuickSwitcherEdgeSwipePolicy.shouldOpen(
                translation: CGPoint(x: -36, y: 4)
            )
        )
        XCTAssertFalse(
            QuickSwitcherEdgeSwipePolicy.shouldOpen(
                translation: CGPoint(x: -72, y: 80)
            )
        )
    }

    func testMinimizedControlDragIsConstrainedTowardOppositeEdge() {
        XCTAssertEqual(
            MinimizedControlPlacement.constrainedTranslation(
                -80,
                currentSide: .trailing,
                containerWidth: 390
            ),
            -80
        )
        XCTAssertEqual(
            MinimizedControlPlacement.constrainedTranslation(
                80,
                currentSide: .trailing,
                containerWidth: 390
            ),
            0
        )
        XCTAssertEqual(
            MinimizedControlPlacement.constrainedTranslation(
                800,
                currentSide: .leading,
                containerWidth: 390
            ),
            306
        )
    }

    func testMinimizedControlSnapsOnlyAfterCommittedHorizontalDrag() {
        XCTAssertEqual(
            MinimizedControlPlacement.resolvedSide(
                currentSide: .trailing,
                translation: -20,
                predictedEndTranslation: -36
            ),
            .trailing
        )
        XCTAssertEqual(
            MinimizedControlPlacement.resolvedSide(
                currentSide: .trailing,
                translation: -52,
                predictedEndTranslation: -78
            ),
            .leading
        )
        XCTAssertEqual(
            MinimizedControlPlacement.resolvedSide(
                currentSide: .leading,
                translation: 52,
                predictedEndTranslation: 78
            ),
            .trailing
        )
    }

    func testPageActionsDrawerKeepsCompactRowsAndVisibleOutsideMargin() {
        XCTAssertEqual(PageActionsDrawerPresentation.rowHeight, 44)
        XCTAssertEqual(PageActionsDrawerPresentation.submenuHorizontalPadding, 12)
        XCTAssertEqual(PageActionsDrawerPresentation.submenuSectionSpacing, 12)
        XCTAssertEqual(PageActionsDrawerPresentation.width(for: 390), 336)
        XCTAssertEqual(PageActionsDrawerPresentation.width(for: 320), 276)
    }

    func testPageActionsDrawerSubmenusStayInOneHierarchicalDrawer() {
        XCTAssertNil(PageActionsDrawerDestination.menu.parent)
        XCTAssertEqual(PageActionsDrawerDestination.siteSettings.parent, .menu)
        XCTAssertEqual(PageActionsDrawerDestination.tabRoles.parent, .menu)
        XCTAssertEqual(PageActionsDrawerDestination.browserSettings.parent, .menu)
        XCTAssertEqual(PageActionsDrawerDestination.manageRoles.parent, .browserSettings)
    }

    func testPageActionsDrawerUsesOwnerApprovedScopeSections() {
        XCTAssertEqual(
            PageActionsDrawerMainSection.allCases.map(\.rawValue),
            ["Site", "Page", "Tab", "App"]
        )
    }

    func testPageActionsDrawerOffersCloseCurrentTabAction() {
        XCTAssertEqual(
            PageActionsDrawerTabPresentation.closeCurrentTabTitle,
            "Close current tab"
        )
        XCTAssertEqual(
            PageActionsDrawerTabPresentation.closeCurrentTabSystemImage,
            "xmark"
        )
    }

    func testMenuVisibilityActionMatchesPerTabMinimizedState() {
        XCTAssertEqual(
            BrowserMenuVisibilityPresentation.actionTitle(menusAreMinimized: false),
            "Minimize Menus"
        )
        XCTAssertEqual(
            BrowserMenuVisibilityPresentation.systemImage(menusAreMinimized: false),
            "rectangle.compress.vertical"
        )
        XCTAssertEqual(
            BrowserMenuVisibilityPresentation.actionTitle(menusAreMinimized: true),
            "Show Menus"
        )
        XCTAssertEqual(
            BrowserMenuVisibilityPresentation.systemImage(menusAreMinimized: true),
            "rectangle.expand.vertical"
        )
    }
}
