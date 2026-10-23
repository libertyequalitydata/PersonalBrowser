import XCTest
@testable import PersonalBrowser

final class TabCardLayoutTests: XCTestCase {
    func testTabGridUsesTwoEqualFlexibleColumns() {
        XCTAssertEqual(TabCardLayout.columns.count, 2)
        XCTAssertEqual(TabCardLayout.gridSpacing, 12)
    }

    func testEveryTabCardUsesOneFixedGeometry() {
        XCTAssertEqual(TabCardLayout.previewHeight, 84)
        XCTAssertEqual(TabCardLayout.contentHeight, 184)
        XCTAssertEqual(TabCardLayout.outerHeight, 196)
        XCTAssertEqual(TabCardLayout.closeOverlapInset, 6)
    }

    func testSavedDestinationUsesSavedLabelAndSavedBookmarksTitle() {
        XCTAssertEqual(TabOverviewSection.bookmarks.title, "Saved")
        XCTAssertEqual(
            TabOverviewSection.bookmarks.navigationTitle(isIncognito: false),
            "Saved Bookmarks"
        )
        XCTAssertEqual(
            TabOverviewSection.bookmarks.navigationTitle(isIncognito: true),
            "Incognito Saved Bookmarks"
        )
    }

    func testTabsFooterSwapsDownloadsAndHistoryPositions() {
        XCTAssertEqual(
            TabOverviewSection.allCases,
            [.tabs, .bookmarks, .downloads, .readingList, .history]
        )
    }
}

final class RoleChipLayoutTests: XCTestCase {
    func testRoleChipVisualsUseCompactRows() {
        XCTAssertEqual(RoleChipLayout.indicatorWidth, 24)
        XCTAssertEqual(RoleChipLayout.visualHeight, 22)
        XCTAssertEqual(RoleChipLayout.rowHeight, 32)
        XCTAssertEqual(RoleChipLayout.verticalSpacing, 0)
    }

    func testRoleChipsWrapWithoutHorizontalScrolling() {
        let rows = RoleChipLayout.rows(
            items: ["Personal", "Personal Browser", "Project C", "Project D", "Research"],
            availableWidth: 94,
            width: { _ in 44 }
        )

        XCTAssertEqual(rows, [
            ["Personal", "Personal Browser"],
            ["Project C", "Project D"],
            ["Research"]
        ])
        XCTAssertGreaterThan(rows.count, 2)
    }

    func testTwoRowsNeedNoOverflowDisclosure() {
        let rows = RoleChipLayout.rows(
            items: ["Personal", "Personal Browser", "Project C", "Project D"],
            availableWidth: 94,
            width: { _ in 44 }
        )

        XCTAssertEqual(rows.count, 2)
    }

    func testRoleSelectionTogglesWithoutNavigationState() {
        let roleID = UUID()
        let otherRoleID = UUID()

        let selected = RoleSelection.toggled(roleID, in: [otherRoleID])
        XCTAssertEqual(selected, [roleID, otherRoleID])

        let deselected = RoleSelection.toggled(roleID, in: selected)
        XCTAssertEqual(deselected, [otherRoleID])
    }

    func testRoleFilterUsesInclusiveOrAndEmptySelectionShowsEverything() {
        let firstRoleID = UUID()
        let secondRoleID = UUID()

        XCTAssertTrue(BrowserRoleFilter.includes(recordRoleIDs: nil, selectedRoleIDs: []))
        XCTAssertFalse(BrowserRoleFilter.includes(recordRoleIDs: nil, selectedRoleIDs: [firstRoleID]))
        XCTAssertTrue(
            BrowserRoleFilter.includes(
                recordRoleIDs: [secondRoleID],
                selectedRoleIDs: [firstRoleID, secondRoleID]
            )
        )
    }
}

final class BrowserLibraryGroupingTests: XCTestCase {
    func testBookmarksAndHistoryGroupByDayWithNewestItemsFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 20))
        )
        let earlierToday = try XCTUnwrap(calendar.date(byAdding: .hour, value: -4, to: now))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let older = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: now))
        let identityID = UUID()
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second"))

        let bookmarkSections = BrowserLibraryGrouping.bookmarkSections(
            for: [
                Bookmark(createdAt: older, url: firstURL, title: "Older", preferredIdentityID: identityID),
                Bookmark(createdAt: earlierToday, url: firstURL, title: "Earlier", preferredIdentityID: identityID),
                Bookmark(createdAt: now, url: secondURL, title: "Newest", preferredIdentityID: identityID),
                Bookmark(createdAt: yesterday, url: firstURL, title: "Yesterday", preferredIdentityID: identityID)
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(Array(bookmarkSections.map(\.title).prefix(2)), ["Today", "Yesterday"])
        XCTAssertEqual(bookmarkSections.first?.bookmarks.map(\.title), ["Newest", "Earlier"])
        XCTAssertEqual(bookmarkSections.count, 3)

        let historySections = BrowserLibraryGrouping.historySections(
            for: [
                BrowserHistoryEntry(visitedAt: earlierToday, identityID: identityID, url: firstURL, title: "Earlier"),
                BrowserHistoryEntry(visitedAt: now, identityID: identityID, url: secondURL, title: "Newest"),
                BrowserHistoryEntry(visitedAt: yesterday, identityID: identityID, url: firstURL, title: "Yesterday")
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(historySections.map(\.title), ["Today", "Yesterday"])
        XCTAssertEqual(historySections.first?.entries.map(\.title), ["Newest", "Earlier"])
    }
}
