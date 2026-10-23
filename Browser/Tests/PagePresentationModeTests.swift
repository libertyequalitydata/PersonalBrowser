import XCTest
@testable import PersonalBrowser

final class PagePresentationModeTests: XCTestCase {
    func testBrowserChromeIsVisibleOnlyForWebPresentation() {
        XCTAssertTrue(PagePresentationMode.web.showsBrowserChrome)
        XCTAssertFalse(PagePresentationMode.reader.showsBrowserChrome)
    }

    func testFloatingReaderActionsAreVisibleOnlyForReaderPresentation() {
        XCTAssertFalse(PagePresentationMode.web.showsReaderActions)
        XCTAssertTrue(PagePresentationMode.reader.showsReaderActions)
    }

    @MainActor
    func testReaderActionsHideDownwardAndReturnUpward() {
        let model = ReaderActionVisibilityModel()

        model.update(offset: 0)
        model.update(offset: 12)
        XCTAssertFalse(model.isVisible)

        model.update(offset: 7)
        XCTAssertTrue(model.isVisible)
    }

    @MainActor
    func testReaderActionsAlwaysReturnAtTop() {
        let model = ReaderActionVisibilityModel()

        model.update(offset: 10)
        model.update(offset: 30)
        XCTAssertFalse(model.isVisible)

        model.update(offset: 0)
        XCTAssertTrue(model.isVisible)
    }

    @MainActor
    func testReaderDragDirectionDirectlyControlsActions() {
        let model = ReaderActionVisibilityModel()

        model.updateDrag(translationHeight: -12)
        XCTAssertFalse(model.isVisible)

        model.updateDrag(translationHeight: 12)
        XCTAssertTrue(model.isVisible)
    }

    func testInlineReaderFooterMatchesSavedReaderSafeAreaPosition() {
        XCTAssertEqual(ReaderFloatingLayout.edgePadding, 8)
        XCTAssertEqual(
            ReaderFloatingLayout.inlineBottomPadding(safeAreaBottom: 34),
            42
        )
        XCTAssertEqual(
            ReaderFloatingLayout.inlineBottomPadding(safeAreaBottom: -4),
            8
        )
    }

    func testReaderPageSwipeNavigatesBackOneScreen() {
        XCTAssertTrue(
            ReaderBackGesture.shouldNavigateBack(
                translation: CGSize(width: 90, height: 8)
            )
        )
        XCTAssertTrue(
            ReaderBackGesture.shouldNavigateBack(
                translation: CGSize(width: 140, height: 24)
            )
        )
        XCTAssertFalse(
            ReaderBackGesture.shouldNavigateBack(
                translation: CGSize(width: 20, height: 90)
            )
        )
        XCTAssertFalse(
            ReaderBackGesture.shouldNavigateBack(
                translation: CGSize(width: -100, height: 4)
            )
        )
    }

    func testSavedArticleBackMotionFollowsRightwardSwipe() {
        XCTAssertEqual(ReadingListNavigationMotion.articleInsertionEdge, .trailing)
        XCTAssertEqual(ReadingListNavigationMotion.articleBackRemovalEdge, .trailing)
    }

    func testReaderLeftSwipeArchivesAndVerticalOrRightSwipeDoesNot() {
        XCTAssertTrue(
            ReaderArchiveGesture.isTrackingArchive(
                translation: CGSize(width: -12, height: 3)
            )
        )
        XCTAssertFalse(
            ReaderArchiveGesture.isTrackingArchive(
                translation: CGSize(width: -12, height: 20)
            )
        )
        XCTAssertTrue(
            ReaderArchiveGesture.shouldArchive(
                translation: CGSize(width: -100, height: 8)
            )
        )
        XCTAssertFalse(
            ReaderArchiveGesture.shouldArchive(
                translation: CGSize(width: -40, height: 4)
            )
        )
        XCTAssertFalse(
            ReaderArchiveGesture.shouldArchive(
                translation: CGSize(width: -100, height: 120)
            )
        )
        XCTAssertFalse(
            ReaderArchiveGesture.shouldArchive(
                translation: CGSize(width: 100, height: 4)
            )
        )
    }

    func testArchivedReaderAdvancesToNextUnreadItem() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            ReadingListSequence.nextItemID(after: first, in: [first, second, third]),
            second
        )
        XCTAssertEqual(
            ReadingListSequence.nextItemID(after: second, in: [first, second, third]),
            third
        )
        XCTAssertEqual(
            ReadingListSequence.nextItemID(after: third, in: [first, second, third]),
            second
        )
        XCTAssertNil(
            ReadingListSequence.nextItemID(after: UUID(), in: [first, second, third])
        )
    }

    func testArchivedReaderAtEndContinuesWithRemainingUnreadItem() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            ReadingListSequence.nextItemID(after: third, in: [first, second, third]),
            second
        )
        XCTAssertNil(
            ReadingListSequence.nextItemID(after: first, in: [first])
        )
    }
}
