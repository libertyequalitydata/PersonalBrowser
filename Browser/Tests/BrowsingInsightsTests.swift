import XCTest
@testable import PersonalBrowser

final class BrowsingInsightsTests: XCTestCase {
    func testSnapshotClipsAttentionAndFiltersByRole() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_792_670_400) // 2026-10-22 12:00 UTC
        let role = UUID()
        let otherRole = UUID()
        let url = try XCTUnwrap(URL(string: "https://news.example.com/story"))
        let matching = BrowserAttentionRecord(
            startedAt: now.addingTimeInterval(-120),
            endedAt: now.addingTimeInterval(-60),
            url: url,
            title: "Story",
            roleIDs: [role]
        )
        let excluded = BrowserAttentionRecord(
            startedAt: now.addingTimeInterval(-60),
            endedAt: now,
            url: try XCTUnwrap(URL(string: "https://social.example.net/feed")),
            title: "Feed",
            roleIDs: [otherRole]
        )
        let history = BrowserHistoryEntry(
            visitedAt: now.addingTimeInterval(-90),
            identityID: UUID(),
            url: url,
            title: "Story",
            roleIDs: [role]
        )

        let snapshot = BrowsingInsightsSnapshot(
            attentionRecords: [matching, excluded],
            history: [history],
            bookmarks: [],
            libraryCount: 4,
            downloads: [],
            mediaUsageRecords: [],
            period: .today,
            selectedRoleIDs: [role],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.activeTime, 60, accuracy: 0.01)
        XCTAssertEqual(snapshot.pagesVisited, 1)
        XCTAssertEqual(snapshot.distinctSites, 1)
        XCTAssertEqual(snapshot.sites.first?.id, "example.com")
        XCTAssertEqual(snapshot.libraryCount, 0)
    }
}
