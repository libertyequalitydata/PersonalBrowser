import XCTest
@testable import PersonalBrowser

@MainActor
final class BrowserStoreTests: XCTestCase {
    func testFreshStoreCreatesNoFixedRolesAndOneUnlabeledNormalTab() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)

        XCTAssertEqual(store.identities.map(\.name), ["Personal"])
        XCTAssertTrue(store.roles.isEmpty)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertFalse(store.tabs[0].isPrivate)
        XCTAssertNotNil(store.tabs[0].identityID)
        XCTAssertEqual(store.tabs[0].roleIDs, [])
        XCTAssertTrue(store.savedBookmarkLists.isEmpty)
        XCTAssertEqual(store.tabs[0].effectiveLinkOpeningPolicy, .followWebsite)
    }

    func testSiteLinkOpeningPolicyPersistsAcrossTabsAndUpdatesLivePages() throws {
        let persistence = MemoryPersistence()
        let suite = "BrowserStoreSiteLinkPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        let store = BrowserStore(
            persistence: persistence,
            siteLinkOpeningPreferences: preferences
        )
        let firstTab = store.createTab(
            url: try XCTUnwrap(URL(string: "https://news.example.com/article"))
        )
        let secondTab = store.createTab(
            url: try XCTUnwrap(URL(string: "https://www.news.example.com/profile")),
            select: false
        )
        let firstPage = store.page(for: firstTab)
        let secondPage = store.page(for: secondTab)

        store.setLinkOpeningPolicy(.subtab, for: firstTab.id)

        XCTAssertEqual(firstPage.linkOpeningPolicy, .subtab)
        XCTAssertEqual(secondPage.linkOpeningPolicy, .subtab)
        XCTAssertEqual(preferences.policy(for: secondTab.url), .subtab)
        XCTAssertTrue(persistence.savedSnapshot?.tabs.allSatisfy { $0.linkOpeningPolicy == nil } == true)

        store.setLinkOpeningPolicy(.followWebsite, for: secondTab.id)

        XCTAssertEqual(firstPage.linkOpeningPolicy, .followWebsite)
        XCTAssertEqual(secondPage.linkOpeningPolicy, .followWebsite)
        XCTAssertFalse(preferences.hasStoredPolicy(for: firstTab.url))
    }

    func testLegacyPerTabLinkPoliciesMigrateUsingMostRecentTabForEachSite() throws {
        let persistence = MemoryPersistence()
        let suite = "BrowserStoreSiteLinkMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let preferences = SiteLinkOpeningPreferences(defaults: defaults)
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let older = BrowserTab(
            identityID: identity.id,
            url: try XCTUnwrap(URL(string: "https://www.example.com/old")),
            linkOpeningPolicy: .sameTab,
            lastActiveAt: Date(timeIntervalSince1970: 100)
        )
        let newer = BrowserTab(
            identityID: identity.id,
            url: try XCTUnwrap(URL(string: "https://example.com/new")),
            linkOpeningPolicy: .subtab,
            lastActiveAt: Date(timeIntervalSince1970: 200)
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [],
            tabs: [older, newer],
            selectedTabID: newer.id,
            history: [],
            bookmarks: [],
            readingList: []
        )

        let store = BrowserStore(
            persistence: persistence,
            siteLinkOpeningPreferences: preferences
        )

        XCTAssertEqual(preferences.policy(for: older.url), .subtab)
        XCTAssertTrue(store.tabs.allSatisfy { $0.linkOpeningPolicy == nil })
        XCTAssertTrue(persistence.savedSnapshot?.tabs.allSatisfy { $0.linkOpeningPolicy == nil } == true)
    }

    func testSavedBookmarkMetadataAndListsPersistWithoutChangingTheURL() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let role = BrowserRole(
            key: "research",
            name: "Research",
            colorHex: "00A88F"
        )
        let bookmark = Bookmark(
            url: try XCTUnwrap(URL(string: "https://example.com/article")),
            title: "Article",
            preferredIdentityID: identity.id
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [role],
            tabs: [BrowserTab(identityID: identity.id, url: bookmark.url)],
            selectedTabID: nil,
            history: [],
            bookmarks: [bookmark],
            readingList: []
        )
        let store = BrowserStore(persistence: persistence)
        let list = try XCTUnwrap(store.addSavedBookmarkList(name: "Research"))

        store.updateBookmarkMetadata(
            bookmark.id,
            note: "Useful evidence for the browser project.",
            roleIDs: [role.id],
            savedListIDs: [list.id]
        )

        let updated = try XCTUnwrap(store.bookmarks.first)
        XCTAssertEqual(updated.url, bookmark.url)
        XCTAssertEqual(updated.note, "Useful evidence for the browser project.")
        XCTAssertEqual(updated.roleIDs, [role.id])
        XCTAssertEqual(updated.savedListIDs, [list.id])
        XCTAssertEqual(persistence.savedSnapshot?.savedBookmarkLists, [list])
        XCTAssertEqual(persistence.savedSnapshot?.bookmarks.first, updated)
        XCTAssertNil(store.addSavedBookmarkList(name: "research"))
    }

    func testSavedListsArchiveAndRestore() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let list = try XCTUnwrap(store.addSavedBookmarkList(name: "Later"))

        store.setSavedBookmarkListArchived(list.id, archived: true)

        XCTAssertTrue(store.activeSavedBookmarkLists.isEmpty)
        XCTAssertEqual(store.archivedSavedBookmarkLists.map(\.id), [list.id])

        store.setSavedBookmarkListArchived(list.id, archived: false)

        XCTAssertEqual(store.activeSavedBookmarkLists.map(\.id), [list.id])
        XCTAssertTrue(store.archivedSavedBookmarkLists.isEmpty)
    }

    func testIncognitoSavedListsRemainSeparateFromNormalSavedLists() throws {
        let store = BrowserStore(persistence: MemoryPersistence())
        let normal = try XCTUnwrap(store.addSavedBookmarkList(name: "Research"))
        let incognito = try XCTUnwrap(
            store.addSavedBookmarkList(name: "Research", isIncognito: true)
        )

        XCTAssertEqual(store.savedBookmarkLists(incognitoOnly: false).map(\.id), [normal.id])
        XCTAssertEqual(store.savedBookmarkLists(incognitoOnly: true).map(\.id), [incognito.id])
        XCTAssertTrue(store.renameSavedBookmarkList(normal.id, name: "Reference"))
        XCTAssertTrue(store.renameSavedBookmarkList(incognito.id, name: "Reference"))
    }

    func testSavedBookmarkCannotLinkToListFromOtherPrivacyMode() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let normalBookmark = Bookmark(
            url: try XCTUnwrap(URL(string: "https://example.com/normal")),
            title: "Normal",
            preferredIdentityID: identity.id
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [],
            tabs: [BrowserTab(identityID: identity.id, url: normalBookmark.url)],
            selectedTabID: nil,
            history: [],
            bookmarks: [normalBookmark],
            readingList: []
        )
        let store = BrowserStore(persistence: persistence)
        let incognitoList = try XCTUnwrap(
            store.addSavedBookmarkList(name: "Private", isIncognito: true)
        )

        store.updateBookmarkMetadata(
            normalBookmark.id,
            note: "",
            roleIDs: [],
            savedListIDs: [incognitoList.id]
        )

        XCTAssertEqual(store.bookmarks.first?.savedListIDs, [])
    }

    func testPrivateTabsAreExcludedFromPersistedSnapshot() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)

        let privateTab = store.createTab(isPrivate: true)

        XCTAssertTrue(privateTab.isPrivate)
        XCTAssertFalse(persistence.savedSnapshot?.tabs.contains(where: { $0.id == privateTab.id }) ?? true)
        XCTAssertNotEqual(persistence.savedSnapshot?.selectedTabID, privateTab.id)
    }

    func testBlankTabsStayActiveButAreExcludedFromTabGridAndPersistence() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let blank = try XCTUnwrap(store.selectedTab)

        XCTAssertTrue(blank.isUncommittedBlank)
        XCTAssertTrue(store.tabs(matchingRoleIDs: []).isEmpty)
        XCTAssertTrue(persistence.savedSnapshot?.tabs.isEmpty == true)
        XCTAssertNil(persistence.savedSnapshot?.selectedTabID)
    }

    func testLegacyPersistedBlankTabsAreDiscardedOnRestore() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let blank = BrowserTab(identityID: identity.id)
        let committed = BrowserTab(
            identityID: identity.id,
            url: try XCTUnwrap(URL(string: "https://example.com"))
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [],
            tabs: [blank, committed],
            selectedTabID: blank.id,
            history: [],
            bookmarks: [],
            readingList: []
        )

        let store = BrowserStore(persistence: persistence)

        XCTAssertEqual(store.tabs.map(\.id), [committed.id])
        XCTAssertEqual(store.selectedTabID, committed.id)
        XCTAssertEqual(persistence.savedSnapshot?.tabs.map(\.id), [committed.id])
    }

    func testBlankTabCanSwitchToIncognitoWithoutLeavingAnExtraTab() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let original = try XCTUnwrap(store.selectedTab)

        let replacement = try XCTUnwrap(store.replaceBlankTab(original.id, isPrivate: true))

        XCTAssertTrue(replacement.isPrivate)
        XCTAssertNil(replacement.identityID)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.selectedTabID, replacement.id)
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertTrue(persistence.savedSnapshot?.tabs.isEmpty == true)
    }

    func testHiddenBrowserControlsPersistPerNormalTabAndRestoreWithItsPage() throws {
        let persistence = MemoryPersistence()
        let firstStore = BrowserStore(persistence: persistence)
        let hiddenTab = firstStore.createTab(url: URL(string: "https://hidden.example")!)
        let visibleTab = firstStore.createTab(url: URL(string: "https://visible.example")!, select: false)

        firstStore.page(for: hiddenTab).hideBrowserControls()

        XCTAssertEqual(
            persistence.savedSnapshot?.tabs.first(where: { $0.id == hiddenTab.id })?.keepsBrowserControlsHidden,
            true
        )
        XCTAssertEqual(
            persistence.savedSnapshot?.tabs.first(where: { $0.id == visibleTab.id })?.keepsBrowserControlsHidden,
            false
        )

        let restoredPersistence = MemoryPersistence()
        restoredPersistence.loadedSnapshot = persistence.savedSnapshot
        let restoredStore = BrowserStore(persistence: restoredPersistence)
        let restoredHiddenTab = try XCTUnwrap(restoredStore.tabs.first(where: { $0.id == hiddenTab.id }))
        let restoredVisibleTab = try XCTUnwrap(restoredStore.tabs.first(where: { $0.id == visibleTab.id }))

        XCTAssertTrue(restoredStore.page(for: restoredHiddenTab).browserControlsPinnedHidden)
        XCTAssertFalse(restoredStore.page(for: restoredVisibleTab).browserControlsPinnedHidden)

        restoredStore.page(for: restoredHiddenTab).revealBrowserControls()
        XCTAssertFalse(
            restoredPersistence.savedSnapshot?.tabs.first(where: { $0.id == hiddenTab.id })?.keepsBrowserControlsHidden
                ?? true
        )
    }

    func testPinnedTabsSortFirstAndMustBeUnpinnedBeforeClosing() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let first = try XCTUnwrap(store.selectedTab)
        let second = store.createTab(url: URL(string: "https://pinned.example")!, select: false)

        store.togglePinned(second.id)

        XCTAssertEqual(store.tabs(matchingRoleIDs: []).first?.id, second.id)
        XCTAssertEqual(store.pinnedTabs.map(\.id), [second.id])
        store.closeTab(second.id)
        XCTAssertTrue(store.tabs.contains(where: { $0.id == second.id }))

        store.togglePinned(second.id)
        store.closeTab(second.id)
        XCTAssertFalse(store.tabs.contains(where: { $0.id == second.id }))
        XCTAssertTrue(store.tabs.contains(where: { $0.id == first.id }))
    }

    func testClosingOnlyCurrentTabCreatesFreshBlankReplacement() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let original = try XCTUnwrap(store.selectedTab)

        store.closeTab(original.id)

        let replacement = try XCTUnwrap(store.selectedTab)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertTrue(replacement.isUncommittedBlank)
    }

    func testIncognitoTabCannotBePinnedOrPersisted() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let incognito = store.createTab(isPrivate: true)

        store.togglePinned(incognito.id)

        XCTAssertFalse(store.tabs.first(where: { $0.id == incognito.id })?.isPinned ?? true)
        XCTAssertFalse(persistence.savedSnapshot?.tabs.contains(where: { $0.id == incognito.id }) ?? true)
    }

    func testPinnedTabDockAppearsOnlyInNormalTabsSection() throws {
        let normal = BrowserTab(
            identityID: UUID(),
            url: try XCTUnwrap(URL(string: "https://example.com")),
            pinnedAt: .now
        )
        let incognito = BrowserTab(
            identityID: nil,
            url: try XCTUnwrap(URL(string: "https://private.example.com")),
            isPrivate: true,
            pinnedAt: .now
        )

        XCTAssertEqual(
            PinnedTabDockPresentation.tabs(
                from: [normal, incognito],
                showsTabsSection: true,
                isPrivate: false
            ),
            [normal]
        )
        XCTAssertTrue(
            PinnedTabDockPresentation.tabs(
                from: [normal],
                showsTabsSection: false,
                isPrivate: false
            ).isEmpty
        )
        XCTAssertTrue(
            PinnedTabDockPresentation.tabs(
                from: [normal],
                showsTabsSection: true,
                isPrivate: true
            ).isEmpty
        )
        XCTAssertEqual(PinnedTabDockPresentation.itemWidth, 72)
        XCTAssertEqual(PinnedTabDockPresentation.iconSpacing, 12)
        XCTAssertEqual(PinnedTabDockPresentation.height, 72)
    }

    func testTabsOverviewFocusesTheSourceTabWhenItIsVisible() {
        let source = BrowserTab(identityID: UUID(), url: URL(string: "https://example.com/source"))
        let other = BrowserTab(identityID: UUID(), url: URL(string: "https://example.com/other"))

        XCTAssertEqual(
            TabOverviewInitialFocus.targetID(
                sourceTabID: source.id,
                visibleTabs: [other, source]
            ),
            source.id
        )
        XCTAssertNil(
            TabOverviewInitialFocus.targetID(
                sourceTabID: source.id,
                visibleTabs: [other]
            )
        )
    }

    func testTabCanMoveToAnotherIdentity() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        store.addIdentity(name: "Work")
        let target = store.identities[1]

        store.moveSelectedTab(to: target.id)

        XCTAssertEqual(store.selectedTab?.identityID, target.id)
    }

    func testNewURLTabUsesRequestedIdentityAndBecomesSelected() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        store.addIdentity(name: "Work")
        let targetIdentity = store.identities[1]
        let url = URLResolver.resolve("example.com/docs")

        let tab = store.createTab(identityID: targetIdentity.id, url: url)

        XCTAssertEqual(tab.identityID, targetIdentity.id)
        XCTAssertEqual(tab.url?.absoluteString, "https://example.com/docs")
        XCTAssertEqual(store.selectedTabID, tab.id)
        XCTAssertEqual(persistence.savedSnapshot?.selectedTabID, tab.id)
    }

    func testExternalWebURLAlwaysCreatesSelectedNormalUnlabeledTab() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        _ = store.createTab(isPrivate: true, url: URL(string: "https://private.example")!)
        let externalURL = try XCTUnwrap(URL(string: "https://example.com:8443/path?q=one#section"))

        let externalTab = try XCTUnwrap(store.openExternalWebURL(externalURL))

        XCTAssertFalse(externalTab.isPrivate)
        XCTAssertEqual(externalTab.identityID, store.identities.first?.id)
        XCTAssertEqual(externalTab.roleIDs, [])
        XCTAssertEqual(externalTab.url?.absoluteString, externalURL.absoluteString)
        XCTAssertEqual(store.selectedTabID, externalTab.id)
        XCTAssertEqual(persistence.savedSnapshot?.selectedTabID, externalTab.id)
    }

    func testExternalWebURLRejectsUnsupportedSchemes() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let startingTabs = store.tabs

        XCTAssertNil(store.openExternalWebURL(URL(string: "mailto:hello@example.com")!))
        XCTAssertEqual(store.tabs, startingTabs)
    }

    func testExternalWebURLCreatesNewTabAndInheritsExactPageMinimizedMenuState() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let url = try XCTUnwrap(URL(string: "https://example.com/home"))
        let restored = BrowserTab(
            identityID: identity.id,
            url: url,
            browserControlsHidden: true
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [],
            tabs: [restored],
            selectedTabID: restored.id,
            history: [],
            bookmarks: [],
            readingList: []
        )
        let store = BrowserStore(persistence: persistence)

        let opened = try XCTUnwrap(store.openExternalWebURL(url))

        XCTAssertNotEqual(opened.id, restored.id)
        XCTAssertTrue(opened.keepsBrowserControlsHidden)
        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.selectedTabID, opened.id)
    }

    func testActiveAttentionStopsAfterIdleWindowAndExcludesIncognito() throws {
        let store = BrowserStore(persistence: MemoryPersistence())
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let normal = store.createTab(url: url)
        let start = Date(timeIntervalSince1970: 1_000)

        store.setApplicationActive(true, at: start)
        store.setWebContentVisible(true, at: start)
        store.recordContentInteraction(for: normal.id, at: start)
        store.checkpointAttention(at: start.addingTimeInterval(90))

        XCTAssertEqual(store.attentionRecords.count, 1)
        XCTAssertEqual(store.attentionRecords[0].duration, 60, accuracy: 0.01)

        let privateTab = store.createTab(isPrivate: true, url: url)
        store.recordContentInteraction(for: privateTab.id, at: start.addingTimeInterval(100))
        store.checkpointAttention(at: start.addingTimeInterval(120))

        XCTAssertEqual(store.attentionRecords.count, 1)
    }

    func testMediaPlaybackTimeRetainsSourceRolesAndCanBeCleared() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let role = BrowserRole(key: "research", name: "Research", colorHex: "00A88F")
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/interview.mp3"))
        let download = BrowserDownloadRecord(
            sourceURL: sourceURL,
            fileName: "interview.mp3",
            localFilename: "interview.mp3",
            identityID: identity.id,
            isIncognito: false,
            state: .completed,
            roleIDs: [role.id]
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [role],
            tabs: [BrowserTab(identityID: identity.id, url: sourceURL)],
            selectedTabID: nil,
            history: [],
            bookmarks: [],
            readingList: [],
            downloads: [download]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localURL = directory.appendingPathComponent(download.localFilename)
        try Data("audio".utf8).write(to: localURL)
        let store = BrowserStore(persistence: persistence, downloadDirectory: directory)
        let item = BrowserMediaItem(
            url: localURL,
            title: "Interview",
            kind: .audio,
            libraryArtifactID: nil
        )

        store.recordMediaPlayback(item, seconds: 15, at: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(store.mediaUsageRecords.count, 1)
        XCTAssertEqual(store.mediaUsageRecords[0].activeSeconds, 15, accuracy: 0.01)
        XCTAssertEqual(store.mediaUsageRecords[0].roleIDs, [role.id])
        XCTAssertEqual(store.mediaUsageRecords[0].sourceURL, URL(string: "https://example.com/"))
        XCTAssertEqual(persistence.savedSnapshot?.mediaUsageRecords, store.mediaUsageRecords)

        let privateDownload = BrowserDownloadRecord(
            sourceURL: try XCTUnwrap(URL(string: "https://private.example/secret.mp3")),
            fileName: "secret.mp3",
            localFilename: "secret.mp3",
            identityID: nil,
            isIncognito: true,
            state: .completed
        )
        store.recordDownloadStarted(privateDownload)
        let privateURL = directory.appendingPathComponent(privateDownload.localFilename)
        try Data("private audio".utf8).write(to: privateURL)
        store.recordMediaPlayback(
            BrowserMediaItem(
                url: privateURL,
                title: "Secret",
                kind: .audio,
                libraryArtifactID: nil
            ),
            seconds: 20,
            at: Date(timeIntervalSince1970: 1_020)
        )

        XCTAssertEqual(store.mediaUsageRecords.count, 1)

        store.clearBrowsingInsights()

        XCTAssertTrue(store.mediaUsageRecords.isEmpty)
        XCTAssertTrue(store.attentionRecords.isEmpty)
    }

    func testRestoredInsightsAreRedactedAndPrunedToNinetyDays() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let now = Date.now
        let recent = now.addingTimeInterval(-3600)
        let expired = now.addingTimeInterval(-(91 * 24 * 3600))
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [],
            tabs: [BrowserTab(identityID: identity.id)],
            selectedTabID: nil,
            history: [],
            bookmarks: [],
            readingList: [],
            attentionRecords: [
                BrowserAttentionRecord(
                    startedAt: recent.addingTimeInterval(-30),
                    endedAt: recent,
                    url: try XCTUnwrap(URL(string: "https://example.com/private/path?token=secret")),
                    title: "Recent"
                ),
                BrowserAttentionRecord(
                    startedAt: expired.addingTimeInterval(-30),
                    endedAt: expired,
                    url: try XCTUnwrap(URL(string: "https://old.example/expired")),
                    title: "Expired"
                )
            ],
            mediaUsageRecords: [
                BrowserMediaUsageRecord(
                    startedAt: recent.addingTimeInterval(-20),
                    endedAt: recent,
                    sourceURL: try XCTUnwrap(URL(string: "https://media.example/audio/file.mp3?signature=secret")),
                    title: "Recent media",
                    kind: .audio,
                    activeSeconds: 20
                ),
                BrowserMediaUsageRecord(
                    startedAt: expired.addingTimeInterval(-20),
                    endedAt: expired,
                    sourceURL: try XCTUnwrap(URL(string: "https://old.example/video.mp4")),
                    title: "Expired media",
                    kind: .video,
                    activeSeconds: 20
                )
            ]
        )

        let store = BrowserStore(persistence: persistence)

        XCTAssertEqual(store.attentionRecords.map(\.url), [URL(string: "https://example.com/")!])
        XCTAssertEqual(store.mediaUsageRecords.map(\.sourceURL), [URL(string: "https://media.example/")!])
        XCTAssertEqual(persistence.savedSnapshot?.attentionRecords, store.attentionRecords)
        XCTAssertEqual(persistence.savedSnapshot?.mediaUsageRecords, store.mediaUsageRecords)
    }

    func testMultipleExternalHandoffsCreateTabsInArrivalOrderAndSelectLatest() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let firstURL = try XCTUnwrap(URL(string: "https://one.example/first"))
        let secondURL = try XCTUnwrap(URL(string: "http://two.example/second"))

        let firstTab = try XCTUnwrap(store.openExternalWebURL(firstURL))
        let secondTab = try XCTUnwrap(store.openExternalWebURL(secondURL))

        XCTAssertLessThan(
            try XCTUnwrap(store.tabs.firstIndex(where: { $0.id == firstTab.id })),
            try XCTUnwrap(store.tabs.firstIndex(where: { $0.id == secondTab.id }))
        )
        XCTAssertEqual(store.selectedTabID, secondTab.id)
        XCTAssertEqual(store.tabs.filter { [firstTab.id, secondTab.id].contains($0.id) }.map(\.url), [firstURL, secondURL])
    }

    func testDownloadOnlyPopupIsRemovedAndParentRemainsSelected() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let parent = try XCTUnwrap(store.selectedTab)
        let parentPage = store.page(for: parent)
        let downloadURL = try XCTUnwrap(URL(string: "https://example.invalid/file.pdf"))

        parentPage.onOpenNewTab?(downloadURL)

        let popup = try XCTUnwrap(store.tabs.first(where: { $0.id != parent.id }))
        XCTAssertEqual(store.selectedTabID, popup.id)

        let record = BrowserDownloadRecord(
            sourceURL: downloadURL,
            fileName: "file.pdf",
            localFilename: "file.pdf",
            identityID: popup.identityID,
            isIncognito: popup.isPrivate
        )
        store.page(for: popup).onDownloadStarted?(record)

        XCTAssertEqual(store.tabs.map(\.id), [parent.id])
        XCTAssertEqual(store.selectedTabID, parent.id)
        XCTAssertEqual(store.downloads.first?.id, record.id)
    }

    func testTabPageVisualMetadataPersistsThroughSnapshotCoding() throws {
        let identityID = UUID()
        let tab = BrowserTab(
            identityID: identityID,
            url: URL(string: "https://example.com/story"),
            title: "Example story",
            siteName: "Example",
            faviconURL: URL(string: "https://example.com/favicon.ico"),
            previewImageURL: URL(string: "https://example.com/social-card.jpg"),
            snapshotFilename: "tab-preview.jpg"
        )
        let snapshot = BrowserSnapshot(
            identities: [BrowserIdentity(id: identityID, name: "Personal", colorHex: "00A88F")],
            roles: nil,
            tabs: [tab],
            selectedTabID: tab.id,
            history: [],
            bookmarks: [],
            readingList: []
        )

        let decoded = try JSONDecoder().decode(BrowserSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded.tabs.first?.siteName, "Example")
        XCTAssertEqual(decoded.tabs.first?.faviconURL?.absoluteString, "https://example.com/favicon.ico")
        XCTAssertEqual(decoded.tabs.first?.previewImageURL?.absoluteString, "https://example.com/social-card.jpg")
        XCTAssertEqual(decoded.tabs.first?.snapshotFilename, "tab-preview.jpg")
    }

    func testNewTabCanRetainSeveralRolesWhileUsingOneWebsiteIdentity() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let selectedRoles = ["Research", "Writing"].compactMap { store.addRole(name: $0)?.id }
        store.addIdentity(name: "Work")
        let identityID = store.identities[1].id

        let tab = store.createTab(identityID: identityID, roleIDs: selectedRoles)

        XCTAssertEqual(tab.identityID, identityID)
        XCTAssertEqual(Set(tab.roleIDs ?? []), Set(selectedRoles))
        XCTAssertEqual(persistence.savedSnapshot?.roles, store.roles)
    }

    func testLegacySnapshotWithoutRolesKeepsTabsUnlabeled() {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let tab = BrowserTab(identityID: identity.id, url: URL(string: "https://example.com")!)
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: nil,
            tabs: [tab],
            selectedTabID: tab.id,
            history: [],
            bookmarks: [],
            readingList: []
        )

        let store = BrowserStore(persistence: persistence)

        XCTAssertEqual(store.tabs.first?.roleIDs, [])
        XCTAssertEqual(persistence.savedSnapshot?.roles, [])
        XCTAssertEqual(persistence.savedSnapshot?.tabs.first?.roleIDs, [])
    }

    func testLegacyFixedRolesAreRemovedFromExistingState() {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let legacyRole = BrowserRole(
            key: "personal",
            name: "Personal",
            colorHex: "00A88F",
            preferredIdentityID: identity.id
        )
        let customRole = BrowserRole(key: "role-custom", name: "Research", colorHex: "56636B")
        let tab = BrowserTab(
            identityID: identity.id,
            url: URL(string: "https://example.com")!,
            roleIDs: [legacyRole.id, customRole.id]
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [legacyRole, customRole],
            tabs: [tab],
            selectedTabID: tab.id,
            history: [],
            bookmarks: [],
            readingList: []
        )

        let store = BrowserStore(persistence: persistence)

        XCTAssertEqual(store.roles.map(\.name), ["Research"])
        XCTAssertEqual(store.tabs.first?.roleIDs, [customRole.id])
        XCTAssertEqual(persistence.savedSnapshot?.roles?.map(\.name), ["Research"])
    }

    func testRoleFilteringUsesAnySelectedRoleAndEmptySelectionShowsAllTabs() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let personalRole = try! XCTUnwrap(store.addRole(name: "Personal"))
        let personalbrowserRole = try! XCTUnwrap(store.addRole(name: "Personal Browser"))
        let projectCRole = try! XCTUnwrap(store.addRole(name: "Project C"))
        let personalIdentity = store.identities[0]
        store.addIdentity(name: "Work", colorHex: "087E99")
        let personalbrowserIdentity = store.identities[1]

        let personalbrowserTab = store.createTab(
            identityID: personalbrowserIdentity.id,
            roleIDs: [personalbrowserRole.id],
            url: URL(string: "https://personalbrowser.example")!
        )
        let combinedTab = store.createTab(
            identityID: personalIdentity.id,
            roleIDs: [personalRole.id, projectCRole.id],
            url: URL(string: "https://combined.example")!
        )

        XCTAssertEqual(store.tabs(matchingRoleIDs: []).count, 2)
        XCTAssertEqual(store.tabs(matchingRoleIDs: [personalbrowserRole.id]).map(\.id), [personalbrowserTab.id])
        XCTAssertTrue(
            store.tabs(matchingRoleIDs: [personalbrowserRole.id, projectCRole.id])
                .map(\.id)
                .contains(combinedTab.id)
        )
    }

    func testRolesAreRankedByOpenTabUsageWithCurrentSelectionFirst() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let personal = try! XCTUnwrap(store.addRole(name: "Personal"))
        let personalbrowser = try! XCTUnwrap(store.addRole(name: "Personal Browser"))
        let projectC = try! XCTUnwrap(store.addRole(name: "Project C"))
        let projectD = try! XCTUnwrap(store.addRole(name: "Project D"))

        _ = store.createTab(roleIDs: [projectC.id])
        _ = store.createTab(roleIDs: [projectC.id])
        _ = store.createTab(roleIDs: [personalbrowser.id])

        XCTAssertEqual(store.rolesByUsage().first?.id, projectC.id)
        XCTAssertEqual(
            store.rolesByUsage(prioritizing: [projectD.id]).first?.id,
            projectD.id
        )
        XCTAssertTrue(store.rolesByUsage().contains(where: { $0.id == personal.id }))
    }

    func testRoleUsageIsPersistedAndRanksBeyondOpenTabBaseline() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let projectD = try! XCTUnwrap(store.addRole(name: "Project D"))
        let usageDate = Date(timeIntervalSince1970: 1_700_000_000)

        store.recordRoleUsage([projectD.id], at: usageDate)
        store.recordRoleUsage([projectD.id], at: usageDate.addingTimeInterval(10))

        let storedRole = store.roles.first(where: { $0.id == projectD.id })
        XCTAssertEqual(storedRole?.usageCount, 2)
        XCTAssertEqual(storedRole?.lastUsedAt, usageDate.addingTimeInterval(10))
        XCTAssertEqual(store.rolesByUsage().first?.id, projectD.id)
        XCTAssertEqual(
            persistence.savedSnapshot?.roles?.first(where: { $0.id == projectD.id })?.usageCount,
            2
        )
    }

    func testUnlabeledTabSurvivesSnapshotRestore() {
        let persistence = MemoryPersistence()
        let initialStore = BrowserStore(persistence: persistence)
        let unlabeledTab = initialStore.createTab(
            identityID: initialStore.identities[0].id,
            roleIDs: [],
            url: URL(string: "https://unlabeled.example")!
        )
        persistence.loadedSnapshot = persistence.savedSnapshot

        let restoredStore = BrowserStore(persistence: persistence)

        XCTAssertEqual(
            restoredStore.tabs.first(where: { $0.id == unlabeledTab.id })?.roleIDs,
            []
        )
    }

    func testNormalDownloadPersistsButIncognitoDownloadDoesNot() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let normal = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/report.pdf")!,
            fileName: "report.pdf",
            localFilename: "report.pdf",
            identityID: store.identities.first?.id,
            isIncognito: false
        )
        let incognito = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/private.pdf")!,
            fileName: "private.pdf",
            localFilename: "private.pdf",
            identityID: nil,
            isIncognito: true
        )

        store.recordDownloadStarted(normal)
        XCTAssertEqual(store.downloadNotice?.message, "Downloading report.pdf")
        XCTAssertEqual(store.downloadNotice?.systemImage, "arrow.down.circle")
        store.recordDownloadStarted(incognito)
        store.updateDownload(id: normal.id, progress: 0.5)
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        store.finishDownload(id: normal.id, byteCount: 4_096, completedAt: completedAt)

        XCTAssertEqual(store.downloadNotice?.message, "Downloaded report.pdf")
        XCTAssertEqual(store.downloadNotice?.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(store.downloads(incognitoOnly: false).first?.state, .completed)
        XCTAssertEqual(store.downloads(incognitoOnly: false).first?.progress, 1)
        XCTAssertEqual(store.downloads(incognitoOnly: false).first?.fileByteCount, 4_096)
        XCTAssertEqual(store.downloads(incognitoOnly: false).first?.completedAt, completedAt)
        XCTAssertEqual(store.downloads(incognitoOnly: true).map(\.id), [incognito.id])
        XCTAssertEqual(persistence.savedSnapshot?.downloads?.map(\.id), [normal.id])
    }

    func testChangingTabRolesDoesNotChangeWebsiteSessionIdentity() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let role = try! XCTUnwrap(store.addRole(name: "Research"))
        let identityID = store.selectedTab?.identityID

        store.setSelectedTabRoles([])
        store.toggleSelectedTabRole(role.id)

        XCTAssertEqual(store.selectedTab?.identityID, identityID)
        XCTAssertEqual(store.selectedTab?.roleIDs, [role.id])
    }

    func testIncognitoFilteringHidesEveryNormalTab() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let roleID = try! XCTUnwrap(store.addRole(name: "Research")).id
        let otherRoleID = try! XCTUnwrap(store.addRole(name: "Writing")).id
        _ = store.createTab(
            identityID: store.identities[0].id,
            roleIDs: [roleID],
            url: URL(string: "https://normal.example")!
        )
        let incognitoTab = store.createTab(
            roleIDs: [roleID],
            isPrivate: true,
            url: URL(string: "https://private.example")!
        )

        XCTAssertEqual(
            store.tabs(matchingRoleIDs: [], incognitoOnly: true).map(\.id),
            [incognitoTab.id]
        )
        XCTAssertEqual(
            store.tabs(matchingRoleIDs: [roleID], incognitoOnly: true).map(\.id),
            [incognitoTab.id]
        )
        XCTAssertTrue(
            store.tabs(matchingRoleIDs: [otherRoleID], incognitoOnly: true).isEmpty
        )
    }

    func testRolesCanBeAddedRenamedArchivedAndRestored() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let role = try XCTUnwrap(store.addRole(name: "Research"))
        store.setSelectedTabRoles([role.id])

        XCTAssertNil(store.addRole(name: "research"))
        XCTAssertTrue(store.renameRole(role.id, name: "Deep Research"))
        XCTAssertEqual(store.activeRoles.first?.name, "Deep Research")

        store.setRoleArchived(role.id, archived: true)
        XCTAssertTrue(store.activeRoles.isEmpty)
        XCTAssertEqual(store.archivedRoles.map(\.id), [role.id])
        XCTAssertEqual(store.selectedTab?.roleIDs, [])

        store.setRoleArchived(role.id, archived: false)
        XCTAssertEqual(store.activeRoles.map(\.id), [role.id])
    }

    func testBookmarksAreSeparatedBetweenNormalAndIncognitoModes() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let url = URL(string: "https://example.com/private-reference")!

        _ = store.createTab(identityID: store.identities[0].id, url: url)
        store.addBookmarkForSelectedPage()
        _ = store.createTab(isPrivate: true, url: url)
        store.addBookmarkForSelectedPage()

        XCTAssertEqual(store.bookmarks(incognitoOnly: false).count, 1)
        XCTAssertEqual(store.bookmarks(incognitoOnly: true).count, 1)
        XCTAssertFalse(store.bookmarks(incognitoOnly: false)[0].isIncognito)
        XCTAssertTrue(store.bookmarks(incognitoOnly: true)[0].isIncognito)
    }

    func testIncognitoHistoryViewIsAlwaysEmpty() {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let tab = BrowserTab(identityID: identity.id)
        let entry = BrowserHistoryEntry(
            identityID: identity.id,
            url: URL(string: "https://example.com")!,
            title: "Example"
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: nil,
            tabs: [tab],
            selectedTabID: tab.id,
            history: [entry],
            bookmarks: [],
            readingList: []
        )
        let store = BrowserStore(persistence: persistence)

        XCTAssertEqual(store.history(incognitoOnly: false), [entry])
        XCTAssertTrue(store.history(incognitoOnly: true).isEmpty)
    }

    func testLegacyHTTPBinVerificationDownloadIsRemovedFromHistoryAndDisk() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let tab = BrowserTab(
            identityID: identity.id,
            url: try XCTUnwrap(URL(string: "https://example.com"))
        )
        let fixture = BrowserDownloadRecord(
            sourceURL: try XCTUnwrap(URL(string: "https://httpbin.org/bytes/32")),
            fileName: "32 (3)",
            localFilename: "32 (3)",
            identityID: identity.id,
            isIncognito: false,
            createdAt: Date(timeIntervalSince1970: 1_791_000_000),
            state: .completed,
            progress: 1,
            fileByteCount: 32
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [],
            tabs: [tab],
            selectedTabID: tab.id,
            history: [],
            bookmarks: [],
            readingList: [],
            downloads: [fixture]
        )
        let downloadDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resumeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: downloadDirectory)
            try? FileManager.default.removeItem(at: resumeDirectory)
        }
        let fixtureURL = downloadDirectory.appendingPathComponent(fixture.localFilename)
        try Data(repeating: 0, count: 32).write(to: fixtureURL)

        let store = BrowserStore(
            persistence: persistence,
            downloadDirectory: downloadDirectory,
            resumeDataDirectory: resumeDirectory
        )

        XCTAssertTrue(store.downloads.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixtureURL.path))
        XCTAssertTrue(persistence.savedSnapshot?.downloads?.isEmpty == true)
    }

    func testLegacyBookmarkDecodesAsNormalBookmark() throws {
        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            preferredIdentityID: nil,
            siteName: "Example Site",
            faviconURL: URL(string: "https://example.com/icon.png")
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(bookmark)) as? [String: Any]
        )
        object.removeValue(forKey: "isIncognito")
        object.removeValue(forKey: "siteName")
        object.removeValue(forKey: "faviconURL")
        object.removeValue(forKey: "roleIDs")
        object.removeValue(forKey: "savedListIDs")
        object.removeValue(forKey: "note")

        let decoded = try JSONDecoder().decode(
            Bookmark.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(decoded.isIncognito)
        XCTAssertNil(decoded.siteName)
        XCTAssertNil(decoded.faviconURL)
        XCTAssertNil(decoded.roleIDs)
        XCTAssertNil(decoded.savedListIDs)
        XCTAssertNil(decoded.note)
    }

    func testLegacySavedListDecodesAsNormalAndActive() throws {
        let list = SavedBookmarkList(name: "Research")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any]
        )
        object.removeValue(forKey: "isIncognito")
        object.removeValue(forKey: "archivedAt")

        let decoded = try JSONDecoder().decode(
            SavedBookmarkList.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(decoded.isIncognito)
        XCTAssertFalse(decoded.isArchived)
    }

    func testRolesFilterTabsBookmarksHistoryAndDownloadsWithInclusiveOr() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let research = BrowserRole(key: "research", name: "Research", colorHex: "56636B")
        let work = BrowserRole(key: "work", name: "Work", colorHex: "56636B")
        let researchURL = try XCTUnwrap(URL(string: "https://example.com/research"))
        let workURL = try XCTUnwrap(URL(string: "https://example.com/work"))
        let tab = BrowserTab(identityID: identity.id, url: researchURL, roleIDs: [research.id])
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [research, work],
            tabs: [tab],
            selectedTabID: tab.id,
            history: [
                BrowserHistoryEntry(identityID: identity.id, url: researchURL, title: "Research", roleIDs: [research.id]),
                BrowserHistoryEntry(identityID: identity.id, url: workURL, title: "Work", roleIDs: [work.id])
            ],
            bookmarks: [
                Bookmark(url: researchURL, title: "Research", preferredIdentityID: identity.id, roleIDs: [research.id]),
                Bookmark(url: workURL, title: "Work", preferredIdentityID: identity.id, roleIDs: [work.id])
            ],
            readingList: [],
            downloads: [
                BrowserDownloadRecord(
                    sourceURL: researchURL,
                    fileName: "research.pdf",
                    localFilename: "research.pdf",
                    identityID: identity.id,
                    isIncognito: false,
                    roleIDs: [research.id]
                ),
                BrowserDownloadRecord(
                    sourceURL: workURL,
                    fileName: "work.pdf",
                    localFilename: "work.pdf",
                    identityID: identity.id,
                    isIncognito: false,
                    roleIDs: [work.id]
                )
            ]
        )
        let store = BrowserStore(persistence: persistence)

        XCTAssertEqual(store.tabs(matchingRoleIDs: [research.id]).map(\.url), [researchURL])
        XCTAssertEqual(store.bookmarks(incognitoOnly: false, matchingRoleIDs: [research.id]).map(\.url), [researchURL])
        XCTAssertEqual(store.history(incognitoOnly: false, matchingRoleIDs: [research.id]).map(\.url), [researchURL])
        XCTAssertEqual(store.downloads(incognitoOnly: false, matchingRoleIDs: [research.id]).map(\.sourceURL), [researchURL])
        XCTAssertEqual(store.bookmarks(incognitoOnly: false, matchingRoleIDs: []).count, 2)
    }

    func testBookmarkAndHistoryRetainCurrentTabRoles() throws {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let role = try XCTUnwrap(store.addRole(name: "Research"))
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let faviconURL = try XCTUnwrap(URL(string: "https://example.com/icon.png"))
        let tab = store.createTab(roleIDs: [role.id], url: url)
        let page = store.page(for: tab)

        page.onNavigationCommitted?(
            url,
            "Article",
            PageVisualMetadata(siteName: "Example Journal", faviconURL: faviconURL)
        )
        store.addBookmarkForSelectedPage()

        XCTAssertEqual(store.history.first?.roleIDs, [role.id])
        XCTAssertEqual(store.history.first?.siteName, "Example Journal")
        XCTAssertEqual(store.history.first?.faviconURL, faviconURL)
        XCTAssertEqual(store.bookmarks.first?.roleIDs, [role.id])
        XCTAssertEqual(store.bookmarks.first?.siteName, "Example Journal")
        XCTAssertEqual(store.bookmarks.first?.faviconURL, faviconURL)
    }

    func testReaderDocumentNormalizesContentSnippetWhitespace() {
        let document = ReaderDocument(
            sourceURL: URL(string: "https://example.com/article")!,
            title: "Article",
            text: "First line.\n\n   Second line with   spaces.",
            capturedIdentityID: nil,
            captureKind: .readableCapture
        )

        XCTAssertEqual(document.contentSnippet, "First line. Second line with spaces.")
    }

    func testReadLaterRetainsFullReaderCaptureAndHeroImage() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let sourceURL = URL(string: "https://example.com/article")!
        let heroURL = URL(string: "https://example.com/article-hero.jpg")!
        let document = ReaderDocument(
            sourceURL: sourceURL,
            title: "Focused article",
            author: "Example Author",
            siteName: "Example Journal",
            text: "First cleaned article paragraph.\n\nSecond cleaned article paragraph.",
            previewImageURL: heroURL,
            capturedIdentityID: store.identities[0].id,
            captureKind: .readableCapture
        )

        let mutation = store.addToReadingList(document)

        XCTAssertEqual(mutation, .inserted)
        XCTAssertEqual(store.readingList.first?.document, document)
        XCTAssertEqual(store.readingList.first?.document.previewImageURL, heroURL)
        XCTAssertEqual(persistence.savedSnapshot?.readingList.first?.document, document)
    }

    func testReadLaterDoesNotDowngradeReadableCaptureToReferenceOnly() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let sourceURL = URL(string: "https://example.com/article")!
        let heroURL = URL(string: "https://example.com/article-hero.jpg")!
        let readable = ReaderDocument(
            sourceURL: sourceURL,
            title: "Focused article",
            text: "A complete cleaned article body that should remain available.",
            previewImageURL: heroURL,
            capturedIdentityID: store.identities[0].id,
            captureKind: .readableCapture
        )
        let failedRefresh = ReaderDocument(
            sourceURL: sourceURL,
            title: "Focused article",
            text: "A readable local capture was not available. The source reference is retained.",
            capturedIdentityID: store.identities[0].id,
            captureKind: .referenceOnly
        )

        XCTAssertEqual(store.addToReadingList(readable), .inserted)
        XCTAssertEqual(store.addToReadingList(failedRefresh), .updated)

        XCTAssertEqual(store.readingList.first?.document, readable)
        XCTAssertEqual(store.readingList.first?.readingState, .queued)
    }

    func testArchivedReadingItemIsHiddenWithoutBeingDeleted() {
        let persistence = MemoryPersistence()
        let store = BrowserStore(persistence: persistence)
        let document = ReaderDocument(
            sourceURL: URL(string: "https://example.com/read")!,
            title: "Read article",
            text: "Article content",
            capturedIdentityID: store.identities[0].id,
            captureKind: .readableCapture
        )
        store.addToReadingList(document)
        let itemID = store.readingList[0].id

        store.archiveReadingItem(itemID)

        XCTAssertTrue(store.activeReadingList.isEmpty)
        XCTAssertEqual(store.archivedReadingList.map(\.id), [itemID])
        XCTAssertEqual(store.readingList.first?.readingState, .consumed)
        XCTAssertEqual(persistence.savedSnapshot?.readingList.first?.readingState, .consumed)
    }

    func testTabsContextStartsFromCurrentNormalTabRolesAndIdentity() {
        let identityID = UUID()
        let roleIDs = [UUID(), UUID()]
        let tab = BrowserTab(identityID: identityID, roleIDs: roleIDs)

        let context = TabOverviewInitialContext.resolve(
            selectedTab: tab,
            fallbackIdentityID: UUID()
        )

        XCTAssertFalse(context.isPrivate)
        XCTAssertEqual(context.identityID, identityID)
        XCTAssertEqual(context.roleIDs, Set(roleIDs))
    }

    func testTabsContextStartsFromCurrentIncognitoTabWithoutPersistentIdentity() {
        let roleID = UUID()
        let tab = BrowserTab(identityID: UUID(), roleIDs: [roleID], isPrivate: true)

        let context = TabOverviewInitialContext.resolve(
            selectedTab: tab,
            fallbackIdentityID: UUID()
        )

        XCTAssertTrue(context.isPrivate)
        XCTAssertNil(context.identityID)
        XCTAssertEqual(context.roleIDs, [roleID])
    }

    func testTabsContextWithoutCurrentTabUsesFallbackIdentityAndNoRoles() {
        let fallbackIdentityID = UUID()

        let context = TabOverviewInitialContext.resolve(
            selectedTab: nil,
            fallbackIdentityID: fallbackIdentityID
        )

        XCTAssertFalse(context.isPrivate)
        XCTAssertEqual(context.identityID, fallbackIdentityID)
        XCTAssertTrue(context.roleIDs.isEmpty)
    }

    func testDownloadedFileAddedToLibraryUsesIndependentDurableCopy() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let download = BrowserDownloadRecord(
            sourceURL: try XCTUnwrap(URL(string: "https://cdn.example.com/briefing.mp4")),
            fileName: "Briefing.mp4",
            localFilename: "Briefing.mp4",
            identityID: identity.id,
            isIncognito: false,
            state: .completed,
            progress: 1,
            mimeType: "video/mp4",
            sourcePageURL: try XCTUnwrap(URL(string: "https://example.com/briefing"))
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity],
            roles: [],
            tabs: [BrowserTab(identityID: identity.id)],
            selectedTabID: nil,
            history: [],
            bookmarks: [],
            readingList: [],
            downloads: [download]
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let library = root.appendingPathComponent("Library", isDirectory: true)
        let resume = root.appendingPathComponent("Resume", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("media".utf8).write(to: downloads.appendingPathComponent(download.localFilename))
        let store = BrowserStore(
            persistence: persistence,
            downloadDirectory: downloads,
            libraryDirectory: library,
            resumeDataDirectory: resume
        )

        let artifact = try store.addDownloadToLibrary(download)
        let libraryURL = try XCTUnwrap(store.libraryFileURL(for: artifact))
        XCTAssertEqual(artifact.kind, .video)
        XCTAssertEqual(artifact.sourceURL, download.sourcePageURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))

        store.setLibraryArtifactArchived(artifact.id, archived: true)
        let restoredArtifact = try store.addDownloadToLibrary(download)
        XCTAssertFalse(restoredArtifact.isArchived)
        XCTAssertEqual(restoredArtifact.id, artifact.id)

        store.removeDownload(download.id)

        XCTAssertNil(store.downloadFileURL(for: download))
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))
        XCTAssertEqual(persistence.savedSnapshot?.libraryArtifacts, [artifact])
    }

    func testLibraryArtifactArchiveTranscriptAndRemovalPersist() throws {
        let persistence = MemoryPersistence()
        let identity = BrowserIdentity(name: "Personal", colorHex: "00A88F")
        let artifact = LibraryArtifact(
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/audio")),
            title: "Interview.m4a",
            localFilename: "Interview.m4a",
            kind: .audio
        )
        persistence.loadedSnapshot = BrowserSnapshot(
            identities: [identity], roles: [],
            tabs: [BrowserTab(identityID: identity.id, url: artifact.sourceURL)], selectedTabID: nil,
            history: [], bookmarks: [], readingList: [], libraryArtifacts: [artifact]
        )
        let library = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: library) }
        try Data("audio".utf8).write(to: library.appendingPathComponent(artifact.localFilename))
        let store = BrowserStore(persistence: persistence, libraryDirectory: library)

        store.setLibraryTranscript("Transcript", localeIdentifier: "en-US", artifactID: artifact.id)
        store.setLibraryArtifactArchived(artifact.id, archived: true)

        XCTAssertTrue(store.activeLibraryArtifacts.isEmpty)
        XCTAssertEqual(store.archivedLibraryArtifacts.first?.transcript, "Transcript")
        XCTAssertEqual(store.archivedLibraryArtifacts.first?.transcriptLocaleIdentifier, "en-US")

        store.removeLibraryArtifact(artifact.id)

        XCTAssertTrue(store.libraryArtifacts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent(artifact.localFilename).path))
        XCTAssertTrue(persistence.savedSnapshot?.libraryArtifacts?.isEmpty == true)
    }
}

private final class MemoryPersistence: BrowserPersisting {
    var loadedSnapshot: BrowserSnapshot?
    var savedSnapshot: BrowserSnapshot?

    func load() throws -> BrowserSnapshot? { loadedSnapshot }
    func save(_ snapshot: BrowserSnapshot) throws { savedSnapshot = snapshot }
}
