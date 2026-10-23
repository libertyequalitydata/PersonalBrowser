import Foundation

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var identities: [BrowserIdentity]
    @Published private(set) var roles: [BrowserRole]
    @Published private(set) var tabs: [BrowserTab]
    @Published var selectedTabID: UUID?
    @Published private(set) var history: [BrowserHistoryEntry]
    @Published private(set) var bookmarks: [Bookmark]
    @Published private(set) var savedBookmarkLists: [SavedBookmarkList]
    @Published private(set) var readingList: [ReadingItem]
    @Published private(set) var libraryArtifacts: [LibraryArtifact]
    @Published private(set) var downloads: [BrowserDownloadRecord]
    @Published private(set) var attentionRecords: [BrowserAttentionRecord]
    @Published private(set) var mediaUsageRecords: [BrowserMediaUsageRecord]
    @Published private(set) var downloadNotice: BrowserDownloadNotice?
    @Published var persistenceError: String?

    private let persistence: BrowserPersisting
    private let siteLinkOpeningPreferences: SiteLinkOpeningPreferences
    private let tabPreviewDirectory: URL
    private let downloadDirectory: URL
    private let libraryDirectory: URL
    private let resumeDataDirectory: URL
    private var pages: [UUID: WebPage] = [:]
    private var popupParentTabIDs: [UUID: UUID] = [:]
    private var detachedDownloadPages: [UUID: WebPage] = [:]
    private var incognitoResumeData: [UUID: Data] = [:]
    private var downloadNoticeTask: Task<Void, Never>?
    private var attentionTask: Task<Void, Never>?
    private var applicationIsActive = false
    private var webContentIsVisible = false
    private var selectedPageWebSurfaceIsActive = true
    private var lastAttentionCheckpointAt: Date?
    private var lastInteractionAtByTabID: [UUID: Date] = [:]
    private var lastAttentionPersistAt: Date?
    private var lastMediaUsagePersistAt: Date?

    init(
        persistence: BrowserPersisting = BrowserPersistence(),
        siteLinkOpeningPreferences: SiteLinkOpeningPreferences = .shared,
        tabPreviewDirectory: URL? = nil,
        downloadDirectory: URL? = nil,
        libraryDirectory: URL? = nil,
        resumeDataDirectory: URL? = nil
    ) {
        self.persistence = persistence
        self.siteLinkOpeningPreferences = siteLinkOpeningPreferences
        var needsRoleCleanup = false
        var needsBlankTabCleanup = false
        var needsLinkPolicyCleanup = false
        var needsInsightsCleanup = false
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.tabPreviewDirectory = tabPreviewDirectory ?? applicationSupport
            .appendingPathComponent("PersonalBrowser", isDirectory: true)
            .appendingPathComponent("TabPreviews", isDirectory: true)
        self.downloadDirectory = downloadDirectory ?? BrowserDownloadSupport.downloadsDirectory()
        self.libraryDirectory = libraryDirectory ?? BrowserDownloadSupport.libraryDirectory()
        self.resumeDataDirectory = resumeDataDirectory ?? BrowserDownloadSupport.resumeDataDirectory()
        var needsDownloadFixtureCleanup = false

        if let snapshot = try? persistence.load(), !snapshot.identities.isEmpty {
            let restoredIdentities = snapshot.identities
            let restoredRoles = snapshot.roles ?? []
            let legacyRoleIDs = Set(
                restoredRoles
                    .filter { Self.legacyDefaultRoleKeys.contains($0.key) }
                    .map(\.id)
            )
            let retainedRoles = restoredRoles.filter { !legacyRoleIDs.contains($0.id) }
            needsRoleCleanup = snapshot.roles == nil || !legacyRoleIDs.isEmpty
            let restoredTabs = snapshot.tabs.filter { !$0.isPrivate && !$0.isUncommittedBlank }
            needsBlankTabCleanup = restoredTabs.count != snapshot.tabs.count
            let legacySitePolicies = Dictionary(
                grouping: restoredTabs.filter { $0.linkOpeningPolicy != nil && $0.url != nil },
                by: { SiteLinkOpeningPreferences.siteKey(for: $0.url) }
            )
            .compactMapValues { tabs -> BrowserTab? in
                tabs.max { $0.lastActiveAt < $1.lastActiveAt }
            }
            for (_, legacyTab) in legacySitePolicies {
                guard let url = legacyTab.url,
                      let policy = legacyTab.linkOpeningPolicy,
                      !siteLinkOpeningPreferences.hasStoredPolicy(for: url) else { continue }
                siteLinkOpeningPreferences.setPolicy(policy, for: url)
            }
            needsLinkPolicyCleanup = restoredTabs.contains { $0.linkOpeningPolicy != nil }

            let migratedTabs = restoredTabs.map { tab in
                var migratedTab = tab
                migratedTab.roleIDs = (migratedTab.roleIDs ?? []).filter { !legacyRoleIDs.contains($0) }
                migratedTab.linkOpeningPolicy = nil
                return migratedTab
            }
            identities = restoredIdentities
            roles = retainedRoles
            tabs = migratedTabs
            selectedTabID = migratedTabs.contains(where: { $0.id == snapshot.selectedTabID })
                ? snapshot.selectedTabID
                : migratedTabs.first?.id
            history = snapshot.history.map { entry in
                var migratedEntry = entry
                migratedEntry.roleIDs = (entry.roleIDs ?? []).filter { !legacyRoleIDs.contains($0) }
                return migratedEntry
            }
            bookmarks = snapshot.bookmarks.map { bookmark in
                var migratedBookmark = bookmark
                migratedBookmark.roleIDs = (bookmark.roleIDs ?? []).filter { !legacyRoleIDs.contains($0) }
                let validSavedListIDs = Set((snapshot.savedBookmarkLists ?? []).map(\.id))
                migratedBookmark.savedListIDs = (bookmark.savedListIDs ?? []).filter {
                    validSavedListIDs.contains($0)
                }
                return migratedBookmark
            }
            savedBookmarkLists = snapshot.savedBookmarkLists ?? []
            readingList = snapshot.readingList
            libraryArtifacts = snapshot.libraryArtifacts ?? []
            downloads = (snapshot.downloads ?? []).map { record in
                var interrupted = record
                interrupted.roleIDs = (record.roleIDs ?? []).filter { !legacyRoleIDs.contains($0) }
                if record.state == .downloading {
                    interrupted.state = .failed
                    interrupted.errorDescription = "The download was interrupted."
                }
                return interrupted
            }
            let insightsCutoff = Self.insightsCutoff(relativeTo: .now)
            attentionRecords = (snapshot.attentionRecords ?? []).compactMap { record in
                guard record.endedAt >= insightsCutoff else {
                    needsInsightsCleanup = true
                    return nil
                }
                var sanitized = record
                let siteURL = Self.siteLevelURL(for: record.url)
                if siteURL != record.url { needsInsightsCleanup = true }
                sanitized.url = siteURL
                return sanitized
            }
            mediaUsageRecords = (snapshot.mediaUsageRecords ?? []).compactMap { record in
                guard record.endedAt >= insightsCutoff else {
                    needsInsightsCleanup = true
                    return nil
                }
                var sanitized = record
                let siteURL = Self.siteLevelURL(for: record.sourceURL)
                if siteURL != record.sourceURL { needsInsightsCleanup = true }
                sanitized.sourceURL = siteURL
                return sanitized
            }
        } else {
            let personal = BrowserIdentity(name: "Personal", colorHex: "00A88F")
            let initialIdentities = [personal]
            let firstTab = BrowserTab(
                identityID: personal.id,
                roleIDs: []
            )
            identities = initialIdentities
            roles = []
            tabs = [firstTab]
            selectedTabID = firstTab.id
            history = []
            bookmarks = []
            savedBookmarkLists = []
            readingList = []
            libraryArtifacts = []
            downloads = []
            attentionRecords = []
            mediaUsageRecords = []
            persist()
        }

        let legacyDownloadFixtures = downloads.filter(BrowserDownloadSupport.isLegacyVerificationFixture)
        if !legacyDownloadFixtures.isEmpty {
            needsDownloadFixtureCleanup = true
            for record in legacyDownloadFixtures {
                try? FileManager.default.removeItem(
                    at: self.downloadDirectory.appendingPathComponent(record.localFilename)
                )
                BrowserDownloadSupport.removeResumeData(
                    filename: record.resumeDataFilename,
                    directory: self.resumeDataDirectory
                )
            }
            let fixtureIDs = Set(legacyDownloadFixtures.map(\.id))
            downloads.removeAll { fixtureIDs.contains($0.id) }
        }

        if tabs.isEmpty {
            let identityID = identities[0].id
            let tab = BrowserTab(
                identityID: identityID,
                roleIDs: []
            )
            tabs = [tab]
            selectedTabID = tab.id
        }

        if needsRoleCleanup
            || needsBlankTabCleanup
            || needsDownloadFixtureCleanup
            || needsLinkPolicyCleanup
            || needsInsightsCleanup {
            persist()
        }
    }

    var selectedTab: BrowserTab? {
        tabs.first(where: { $0.id == selectedTabID })
    }

    var selectedIdentity: BrowserIdentity? {
        guard let identityID = selectedTab?.identityID else { return nil }
        return identities.first(where: { $0.id == identityID })
    }

    var activeRoles: [BrowserRole] {
        roles.filter { !$0.isArchived }
    }

    var archivedRoles: [BrowserRole] {
        roles.filter(\.isArchived)
    }

    var activeSavedBookmarkLists: [SavedBookmarkList] {
        savedBookmarkLists
            .filter { !$0.isArchived }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var archivedSavedBookmarkLists: [SavedBookmarkList] {
        savedBookmarkLists
            .filter(\.isArchived)
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    func savedBookmarkLists(incognitoOnly: Bool, archived: Bool = false) -> [SavedBookmarkList] {
        savedBookmarkLists
            .filter { $0.isIncognito == incognitoOnly && $0.isArchived == archived }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var pinnedTabs: [BrowserTab] {
        tabs
            .filter { !$0.isPrivate && $0.isPinned }
            .sorted { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
    }

    func rolesByUsage(prioritizing selectedRoleIDs: Set<UUID> = []) -> [BrowserRole] {
        let active = activeRoles
        let originalIndexes = Dictionary(uniqueKeysWithValues: active.enumerated().map { ($1.id, $0) })
        let usage = Dictionary(grouping: tabs.flatMap { tab in
            (tab.roleIDs ?? []).map { roleID in (roleID, tab.lastActiveAt) }
        }, by: \.0)

        return active.sorted { left, right in
            let leftSelected = selectedRoleIDs.contains(left.id)
            let rightSelected = selectedRoleIDs.contains(right.id)
            if leftSelected != rightSelected { return leftSelected }

            let leftUsage = usage[left.id, default: []]
            let rightUsage = usage[right.id, default: []]
            let leftUsageCount = left.usageCount ?? leftUsage.count
            let rightUsageCount = right.usageCount ?? rightUsage.count
            if leftUsageCount != rightUsageCount { return leftUsageCount > rightUsageCount }

            let leftRecency = left.lastUsedAt ?? leftUsage.map(\.1).max() ?? .distantPast
            let rightRecency = right.lastUsedAt ?? rightUsage.map(\.1).max() ?? .distantPast
            if leftRecency != rightRecency { return leftRecency > rightRecency }

            return originalIndexes[left.id, default: .max] < originalIndexes[right.id, default: .max]
        }
    }

    var activeReadingList: [ReadingItem] {
        readingList.filter { $0.readingState != .consumed }
    }

    var archivedReadingList: [ReadingItem] {
        readingList.filter { $0.readingState == .consumed }
    }

    var activeLibraryArtifacts: [LibraryArtifact] {
        libraryArtifacts.filter { !$0.isArchived }
    }

    var archivedLibraryArtifacts: [LibraryArtifact] {
        libraryArtifacts.filter(\.isArchived)
    }

    func tabs(
        matchingRoleIDs selectedRoleIDs: Set<UUID>,
        incognitoOnly: Bool = false
    ) -> [BrowserTab] {
        let committedTabs = tabs.filter { !$0.isUncommittedBlank }
        let modeTabs = incognitoOnly ? committedTabs.filter(\.isPrivate) : committedTabs
        let filtered = selectedRoleIDs.isEmpty
            ? modeTabs
            : modeTabs.filter {
                BrowserRoleFilter.includes(recordRoleIDs: $0.roleIDs, selectedRoleIDs: selectedRoleIDs)
            }
        return filtered.enumerated().sorted { left, right in
            if left.element.isPinned != right.element.isPinned {
                return left.element.isPinned
            }
            if left.element.isPinned, right.element.isPinned {
                return (left.element.pinnedAt ?? .distantPast) < (right.element.pinnedAt ?? .distantPast)
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    func downloads(
        incognitoOnly: Bool,
        matchingRoleIDs selectedRoleIDs: Set<UUID> = []
    ) -> [BrowserDownloadRecord] {
        downloads.filter {
            $0.isIncognito == incognitoOnly
                && BrowserRoleFilter.includes(recordRoleIDs: $0.roleIDs, selectedRoleIDs: selectedRoleIDs)
        }
    }

    func bookmarks(
        incognitoOnly: Bool,
        matchingRoleIDs selectedRoleIDs: Set<UUID> = []
    ) -> [Bookmark] {
        bookmarks.filter {
            $0.isIncognito == incognitoOnly
                && BrowserRoleFilter.includes(recordRoleIDs: $0.roleIDs, selectedRoleIDs: selectedRoleIDs)
        }
    }

    func history(
        incognitoOnly: Bool,
        matchingRoleIDs selectedRoleIDs: Set<UUID> = []
    ) -> [BrowserHistoryEntry] {
        guard !incognitoOnly else { return [] }
        return history.filter {
            BrowserRoleFilter.includes(recordRoleIDs: $0.roleIDs, selectedRoleIDs: selectedRoleIDs)
        }
    }

    func page(for tab: BrowserTab) -> WebPage {
        if let page = pages[tab.id] { return page }
        let page = WebPage(
            tab: tab,
            siteLinkOpeningPreferences: siteLinkOpeningPreferences,
            downloadDirectory: downloadDirectory
        )
        page.onNavigationCommitted = { [weak self] url, title, metadata in
            self?.recordNavigation(tabID: tab.id, url: url, title: title, metadata: metadata)
        }
        page.onOpenNewTab = { [weak self] url in
            guard let self,
                  let currentTab = self.tabs.first(where: { $0.id == tab.id }) else { return }
            let newTab = self.createTab(
                identityID: currentTab.identityID,
                roleIDs: currentTab.roleIDs,
                isPrivate: currentTab.isPrivate,
                url: url,
                select: true
            )
            self.popupParentTabIDs[newTab.id] = currentTab.id
            _ = self.page(for: newTab)
        }
        page.onOpenLinkInNewTab = { [weak self] url in
            guard let self,
                  let currentTab = self.tabs.first(where: { $0.id == tab.id }) else { return }
            let newTab = self.createTab(
                identityID: currentTab.identityID,
                roleIDs: currentTab.roleIDs,
                isPrivate: currentTab.isPrivate,
                url: url,
                select: false
            )
            _ = self.page(for: newTab)
        }
        page.onOpenLinkInSelectedTab = { [weak self] url in
            guard let self,
                  let currentTab = self.tabs.first(where: { $0.id == tab.id }) else { return }
            let newTab = self.createTab(
                identityID: currentTab.identityID,
                roleIDs: currentTab.roleIDs,
                isPrivate: currentTab.isPrivate,
                url: url,
                select: true
            )
            _ = self.page(for: newTab)
        }
        page.onOpenLinkInIncognito = { [weak self] url in
            guard let self,
                  let currentTab = self.tabs.first(where: { $0.id == tab.id }) else { return }
            let newTab = self.createTab(
                roleIDs: currentTab.roleIDs,
                isPrivate: true,
                url: url,
                select: false
            )
            _ = self.page(for: newTab)
        }
        page.onAddLinkToReadingList = { [weak self] url in
            guard let self else { return }
            let host = url.host ?? url.absoluteString
            _ = self.addToReadingList(
                ReaderDocument(
                    sourceURL: url,
                    title: host,
                    siteName: url.host,
                    text: "Open the source to capture its readable article content.",
                    capturedIdentityID: tab.isPrivate ? nil : tab.identityID,
                    captureKind: .referenceOnly
                )
            )
        }
        page.onDownloadStarted = { [weak self] record in
            guard let self else { return }
            var contextualRecord = record
            if contextualRecord.roleIDs == nil {
                contextualRecord.roleIDs = self.tabs.first(where: { $0.id == tab.id })?.roleIDs ?? []
            }
            self.recordDownloadStarted(contextualRecord)
            self.detachDownloadOnlyPopup(tabID: tab.id, downloadID: record.id)
        }
        page.onDownloadProgress = { [weak self] id, progress in
            self?.updateDownload(id: id, progress: progress)
        }
        page.onDownloadFinished = { [weak self] id, byteCount, completedAt in
            self?.finishDownload(id: id, byteCount: byteCount, completedAt: completedAt)
            self?.detachedDownloadPages[id] = nil
        }
        page.onDownloadFailed = { [weak self] id, message, cancelled, resumeData in
            self?.failDownload(id: id, message: message, cancelled: cancelled, resumeData: resumeData)
            self?.detachedDownloadPages[id] = nil
        }
        page.onBrowserControlsHiddenChanged = { [weak self] hidden in
            self?.setBrowserControlsHidden(hidden, for: tab.id)
        }
        pages[tab.id] = page
        return page
    }

    func snapshotURL(for tab: BrowserTab) -> URL? {
        guard let snapshotFilename = tab.snapshotFilename else { return nil }
        let url = tabPreviewDirectory.appendingPathComponent(snapshotFilename, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func prepareMissingTabVisuals() {
        for tab in tabs where tab.url != nil && tab.previewImageURL == nil && tab.snapshotFilename == nil {
            _ = page(for: tab)
        }
    }

    @discardableResult
    func createTab(
        identityID: UUID? = nil,
        roleIDs: [UUID]? = nil,
        isPrivate: Bool = false,
        url: URL? = nil,
        browserControlsHidden: Bool = false,
        select: Bool = true
    ) -> BrowserTab {
        if select { checkpointAttention(at: .now) }
        let resolvedIdentity = isPrivate ? nil : (identityID ?? identities.first?.id)
        let validRoleIDs = Set(activeRoles.map(\.id))
        let resolvedRoleIDs = (roleIDs ?? []).filter { validRoleIDs.contains($0) }
        let tab = BrowserTab(
            identityID: resolvedIdentity,
            url: url,
            faviconURL: URLResolver.conventionalFaviconURL(for: url),
            roleIDs: resolvedRoleIDs,
            isPrivate: isPrivate,
            browserControlsHidden: browserControlsHidden
        )
        tabs.append(tab)
        recordRoleUsage(resolvedRoleIDs, persistChanges: false)
        if select {
            selectedTabID = tab.id
        }
        persist()
        return tab
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        checkpointAttention(at: .now)
        selectedTabID = id
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs[index].lastActiveAt = .now
            recordRoleUsage(tabs[index].roleIDs ?? [], persistChanges: false)
            lastInteractionAtByTabID[id] = .now
        }
        persist()
    }

    func togglePinned(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].isPrivate else { return }
        tabs[index].pinnedAt = tabs[index].isPinned ? nil : .now
        persist()
    }

    func setBrowserControlsHidden(_ hidden: Bool, for tabID: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }),
              tabs[index].keepsBrowserControlsHidden != hidden else { return }
        tabs[index].browserControlsHidden = hidden ? true : nil
        persist()
    }

    func setLinkOpeningPolicy(_ policy: BrowserLinkOpeningPolicy, for tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let sourceURL = pages[tabID]?.url ?? tab.url else { return }
        siteLinkOpeningPreferences.setPolicy(policy, for: sourceURL)
        for page in pages.values {
            page.refreshLinkOpeningPolicy()
        }
    }

    func closeTab(_ id: UUID) {
        guard tabs.first(where: { $0.id == id })?.isPinned != true else { return }
        if let tab = tabs.first(where: { $0.id == id }), let snapshotURL = snapshotURL(for: tab) {
            try? FileManager.default.removeItem(at: snapshotURL)
        }
        pages[id] = nil
        popupParentTabIDs[id] = nil
        tabs.removeAll(where: { $0.id == id })
        if selectedTabID == id {
            selectedTabID = tabs.max(by: { $0.lastActiveAt < $1.lastActiveAt })?.id
        }
        if tabs.isEmpty {
            createTab()
        } else {
            persist()
        }
    }

    @discardableResult
    func replaceBlankTab(_ id: UUID, isPrivate: Bool) -> BrowserTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              tabs[index].isUncommittedBlank else { return nil }
        let previous = tabs[index]
        let replacement = BrowserTab(
            identityID: isPrivate ? nil : (previous.identityID ?? identities.first?.id),
            roleIDs: previous.roleIDs ?? [],
            isPrivate: isPrivate
        )
        pages[id] = nil
        tabs[index] = replacement
        selectedTabID = replacement.id
        persist()
        return replacement
    }

    func duplicateSelectedTab(as identityID: UUID?, privateMode: Bool = false) {
        createTab(
            identityID: identityID,
            roleIDs: selectedTab?.roleIDs,
            isPrivate: privateMode,
            url: selectedTab?.url
        )
    }

    func moveSelectedTab(to identityID: UUID) {
        guard let selectedTabID, let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].identityID = identityID
        tabs[index].isPrivate = false
        pages[selectedTabID] = nil
        persist()
    }

    func setSelectedTabRoles(_ roleIDs: [UUID]) {
        guard let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        checkpointAttention(at: .now)
        let validRoleIDs = Set(activeRoles.map(\.id))
        tabs[index].roleIDs = roleIDs.filter { validRoleIDs.contains($0) }
        updateRecentHistoryRoleContext(for: tabs[index])
        recordRoleUsage(tabs[index].roleIDs ?? [], persistChanges: false)
        persist()
    }

    func toggleSelectedTabRole(_ roleID: UUID) {
        guard activeRoles.contains(where: { $0.id == roleID }),
              let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        checkpointAttention(at: .now)
        var roleIDs = tabs[index].roleIDs ?? []
        if let roleIndex = roleIDs.firstIndex(of: roleID) {
            roleIDs.remove(at: roleIndex)
        } else {
            roleIDs.append(roleID)
            recordRoleUsage([roleID], persistChanges: false)
        }
        tabs[index].roleIDs = roleIDs
        updateRecentHistoryRoleContext(for: tabs[index])
        persist()
    }

    @discardableResult
    func addRole(name: String) -> BrowserRole? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !roles.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return nil
        }
        let role = BrowserRole(
            key: "role-\(UUID().uuidString.lowercased())",
            name: trimmed,
            colorHex: "56636B"
        )
        roles.append(role)
        persist()
        return role
    }

    @discardableResult
    func renameRole(_ id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = roles.firstIndex(where: { $0.id == id }),
              !roles.contains(where: {
                  $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
              }) else { return false }
        roles[index].name = trimmed
        persist()
        return true
    }

    func setRoleArchived(_ id: UUID, archived: Bool) {
        guard let index = roles.firstIndex(where: { $0.id == id }),
              roles[index].isArchived != archived else { return }
        roles[index].isArchived = archived
        if archived {
            for tabIndex in tabs.indices {
                tabs[tabIndex].roleIDs = (tabs[tabIndex].roleIDs ?? []).filter { $0 != id }
            }
            for historyIndex in history.indices {
                history[historyIndex].roleIDs = (history[historyIndex].roleIDs ?? []).filter { $0 != id }
            }
            for bookmarkIndex in bookmarks.indices {
                bookmarks[bookmarkIndex].roleIDs = (bookmarks[bookmarkIndex].roleIDs ?? []).filter { $0 != id }
            }
            for downloadIndex in downloads.indices {
                downloads[downloadIndex].roleIDs = (downloads[downloadIndex].roleIDs ?? []).filter { $0 != id }
            }
        }
        persist()
    }

    func recordRoleUsage(
        _ roleIDs: [UUID],
        at date: Date = .now,
        persistChanges: Bool = true
    ) {
        let uniqueIDs = Set(roleIDs)
        guard !uniqueIDs.isEmpty else { return }
        var changed = false
        for index in roles.indices where uniqueIDs.contains(roles[index].id) && !roles[index].isArchived {
            roles[index].usageCount = (roles[index].usageCount ?? 0) + 1
            roles[index].lastUsedAt = date
            changed = true
        }
        if changed, persistChanges { persist() }
    }

    func cancelDownload(_ id: UUID) {
        for page in pages.values where page.cancelDownload(id) {
            return
        }
        _ = detachedDownloadPages[id]?.cancelDownload(id)
    }

    @discardableResult
    func retryDownload(_ id: UUID) -> Bool {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return false }
        let record = downloads[index]
        guard record.state != .downloading else { return false }

        let candidateTabs = tabs.filter {
            $0.isPrivate == record.isIncognito
                && (record.isIncognito || $0.identityID == record.identityID)
        }
        let tab = candidateTabs.first(where: { $0.id == selectedTabID }) ?? candidateTabs.first
        guard let tab else {
            downloads[index].errorDescription = "The original browsing session is no longer available."
            persist()
            return false
        }

        let resumeData = record.isIncognito
            ? incognitoResumeData[id]
            : BrowserDownloadSupport.loadResumeData(
                filename: record.resumeDataFilename,
                directory: resumeDataDirectory
            )
        if resumeData != nil {
            clearResumeData(for: record)
            downloads[index].resumeDataFilename = nil
        }
        downloads[index].state = .downloading
        downloads[index].progress = 0
        downloads[index].errorDescription = nil
        downloads[index].completedAt = nil
        downloads[index].fileByteCount = nil
        persist()

        guard page(for: tab).retryDownload(downloads[index], resumeData: resumeData) else {
            downloads[index].state = .failed
            downloads[index].errorDescription = "This download cannot be retried."
            persist()
            return false
        }
        return true
    }

    func removeDownload(_ id: UUID) {
        guard let record = downloads.first(where: { $0.id == id }) else { return }
        if record.state == .downloading {
            cancelDownload(id)
        }
        if let url = downloadFileURL(for: record) {
            try? FileManager.default.removeItem(at: url)
        }
        clearResumeData(for: record)
        downloads.removeAll(where: { $0.id == id })
        persist()
    }

    func libraryArtifact(for download: BrowserDownloadRecord) -> LibraryArtifact? {
        libraryArtifacts.first { $0.sourceDownloadID == download.id }
    }

    func libraryFileURL(for artifact: LibraryArtifact) -> URL? {
        let url = libraryDirectory.appendingPathComponent(artifact.localFilename, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func addDownloadToLibrary(_ record: BrowserDownloadRecord) throws -> LibraryArtifact {
        if let existing = libraryArtifact(for: record) {
            if existing.isArchived {
                setLibraryArtifactArchived(existing.id, archived: false)
                showNotice("Restored to Library", systemImage: "books.vertical.fill")
                return libraryArtifacts.first(where: { $0.id == existing.id }) ?? existing
            }
            return existing
        }
        guard record.state == .completed,
              let sourceFileURL = downloadFileURL(for: record) else {
            throw LibraryArtifactError.fileUnavailable
        }
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        let destination = try BrowserDownloadSupport.uniqueDestinationURL(
            suggestedFilename: record.fileName,
            sourceURL: record.sourceURL,
            directory: libraryDirectory
        )
        try FileManager.default.copyItem(at: sourceFileURL, to: destination)
        let artifact = LibraryArtifact(
            sourceDownloadID: record.id,
            sourceURL: record.sourcePageURL ?? record.sourceURL,
            title: record.fileName,
            localFilename: destination.lastPathComponent,
            kind: BrowserDownloadSupport.libraryKind(for: record),
            mimeType: record.mimeType,
            typeIdentifier: record.typeIdentifier,
            isIncognito: record.isIncognito
        )
        libraryArtifacts.insert(artifact, at: 0)
        persist()
        showNotice("Added to Library", systemImage: "books.vertical.fill")
        return artifact
    }

    func removeLibraryArtifact(_ id: UUID) {
        guard let artifact = libraryArtifacts.first(where: { $0.id == id }) else { return }
        if let url = libraryFileURL(for: artifact) {
            try? FileManager.default.removeItem(at: url)
        }
        libraryArtifacts.removeAll { $0.id == id }
        persist()
    }

    func setLibraryArtifactArchived(_ id: UUID, archived: Bool) {
        guard let index = libraryArtifacts.firstIndex(where: { $0.id == id }) else { return }
        libraryArtifacts[index].archivedAt = archived ? .now : nil
        persist()
    }

    func setLibraryTranscript(
        _ transcript: String,
        localeIdentifier: String,
        artifactID: UUID
    ) {
        guard let index = libraryArtifacts.firstIndex(where: { $0.id == artifactID }) else { return }
        libraryArtifacts[index].transcript = transcript
        libraryArtifacts[index].transcriptLocaleIdentifier = localeIdentifier
        persist()
    }

    func downloadFileURL(for record: BrowserDownloadRecord) -> URL? {
        let url = downloadDirectory
            .appendingPathComponent(record.localFilename, isDirectory: false)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func addIdentity(name: String, colorHex: String = "00A88F") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        identities.append(BrowserIdentity(name: trimmed, colorHex: colorHex))
        persist()
    }

    func addBookmarkForSelectedPage() {
        guard let tab = selectedTab, let url = tab.url else { return }
        if let existing = bookmarks.firstIndex(where: {
            $0.url == url && $0.isIncognito == tab.isPrivate
        }) {
            bookmarks.remove(at: existing)
        } else {
            bookmarks.insert(
                Bookmark(
                    url: url,
                    title: tab.title,
                    preferredIdentityID: tab.isPrivate ? nil : tab.identityID,
                    isIncognito: tab.isPrivate,
                    siteName: tab.siteName,
                    faviconURL: tab.faviconURL ?? URLResolver.conventionalFaviconURL(for: url),
                    roleIDs: tab.roleIDs ?? []
                ),
                at: 0
            )
        }
        persist()
    }

    func isBookmarked(_ url: URL?, isIncognito: Bool? = nil) -> Bool {
        guard let url else { return false }
        let targetMode = isIncognito ?? selectedTab?.isPrivate ?? false
        return bookmarks.contains(where: { $0.url == url && $0.isIncognito == targetMode })
    }

    @discardableResult
    func addSavedBookmarkList(name: String, isIncognito: Bool = false) -> SavedBookmarkList? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !savedBookmarkLists.contains(where: {
                  $0.isIncognito == isIncognito
                      && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }) else { return nil }
        let list = SavedBookmarkList(name: trimmed, isIncognito: isIncognito)
        savedBookmarkLists.append(list)
        persist()
        return list
    }

    @discardableResult
    func renameSavedBookmarkList(_ id: UUID, name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = savedBookmarkLists.firstIndex(where: { $0.id == id }),
              !trimmed.isEmpty,
              !savedBookmarkLists.contains(where: {
                  $0.id != id
                      && $0.isIncognito == savedBookmarkLists[index].isIncognito
                      && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
              }) else { return false }
        savedBookmarkLists[index].name = trimmed
        persist()
        return true
    }

    func setSavedBookmarkListArchived(_ id: UUID, archived: Bool) {
        guard let index = savedBookmarkLists.firstIndex(where: { $0.id == id }) else { return }
        savedBookmarkLists[index].archivedAt = archived ? .now : nil
        persist()
    }

    func updateBookmarkMetadata(
        _ id: UUID,
        note: String,
        roleIDs: [UUID],
        savedListIDs: [UUID]
    ) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let validRoleIDs = Set(activeRoles.map(\.id))
        let validSavedListIDs = Set(
            savedBookmarkLists
                .filter { $0.isIncognito == bookmarks[index].isIncognito }
                .map(\.id)
        )
        let normalizedNote = String(
            note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280)
        )
        bookmarks[index].note = normalizedNote.isEmpty ? nil : normalizedNote
        bookmarks[index].roleIDs = roleIDs.filter { validRoleIDs.contains($0) }
        bookmarks[index].savedListIDs = savedListIDs.filter { validSavedListIDs.contains($0) }
        recordRoleUsage(bookmarks[index].roleIDs ?? [], persistChanges: false)
        persist()
    }

    func removeBookmark(_ id: UUID) {
        guard bookmarks.contains(where: { $0.id == id }) else { return }
        bookmarks.removeAll { $0.id == id }
        persist()
    }

    func open(_ bookmark: Bookmark) {
        if bookmark.isIncognito {
            let tab = createTab(isPrivate: true, url: bookmark.url)
            _ = page(for: tab)
        } else {
            open(bookmark.url, preferredIdentityID: bookmark.preferredIdentityID)
        }
    }

    @discardableResult
    func addToReadingList(_ document: ReaderDocument) -> ReadingListMutation {
        if let index = readingList.firstIndex(where: { $0.document.sourceURL == document.sourceURL }) {
            if shouldReplaceReadingCapture(
                existing: readingList[index].document,
                with: document
            ) {
                readingList[index].document = document
            }
            readingList[index].readingState = .queued
            persist()
            return .updated
        } else {
            readingList.insert(ReadingItem(document: document), at: 0)
            persist()
            return .inserted
        }
    }

    func markReadingItem(_ id: UUID, state: ReadingState) {
        guard let index = readingList.firstIndex(where: { $0.id == id }) else { return }
        readingList[index].readingState = state
        persist()
    }

    func archiveReadingItem(_ id: UUID) {
        markReadingItem(id, state: .consumed)
    }

    func removeReadingItem(_ id: UUID) {
        readingList.removeAll(where: { $0.id == id })
        persist()
    }

    private func shouldReplaceReadingCapture(
        existing: ReaderDocument,
        with candidate: ReaderDocument
    ) -> Bool {
        if existing.captureKind == .readableCapture,
           candidate.captureKind == .referenceOnly {
            return false
        }

        if candidate.captureKind == .readableCapture,
           existing.captureKind == .referenceOnly {
            return true
        }

        let existingScore = existing.text.count + (existing.previewImageURL == nil ? 0 : 400)
        let candidateScore = candidate.text.count + (candidate.previewImageURL == nil ? 0 : 400)
        return candidateScore >= existingScore
    }

    func open(_ url: URL, preferredIdentityID: UUID? = nil) {
        if let selectedTab, !selectedTab.isPrivate {
            let targetIdentity = preferredIdentityID ?? selectedTab.identityID
            if targetIdentity == selectedTab.identityID {
                page(for: selectedTab).load(url)
                return
            }
        }
        let tab = createTab(identityID: preferredIdentityID, url: url)
        _ = page(for: tab)
    }

    @discardableResult
    func openExternalWebURL(_ url: URL) -> BrowserTab? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let ownerSessionID = identities.first?.id else { return nil }
        let inheritedControlsHidden = tabs
            .filter({ !$0.isPrivate && $0.url == url })
            .max(by: { $0.lastActiveAt < $1.lastActiveAt })?
            .keepsBrowserControlsHidden ?? false
        return createTab(
            identityID: ownerSessionID,
            roleIDs: [],
            isPrivate: false,
            url: url,
            browserControlsHidden: inheritedControlsHidden
        )
    }

    func setApplicationActive(_ active: Bool, at date: Date = .now) {
        if !active { checkpointAttention(at: date) }
        applicationIsActive = active
        lastAttentionCheckpointAt = date
        if active {
            if let selectedTabID { lastInteractionAtByTabID[selectedTabID] = date }
            startAttentionTimer()
        } else {
            attentionTask?.cancel()
            attentionTask = nil
            persist()
        }
    }

    func setWebContentVisible(_ visible: Bool, at date: Date = .now) {
        if !visible { checkpointAttention(at: date) }
        webContentIsVisible = visible
        lastAttentionCheckpointAt = date
        if visible, let selectedTabID { lastInteractionAtByTabID[selectedTabID] = date }
    }

    func setSelectedPageWebSurfaceActive(_ active: Bool, at date: Date = .now) {
        if !active { checkpointAttention(at: date) }
        selectedPageWebSurfaceIsActive = active
        lastAttentionCheckpointAt = date
        if active, let selectedTabID { lastInteractionAtByTabID[selectedTabID] = date }
    }

    func recordContentInteraction(for tabID: UUID, at date: Date = .now) {
        checkpointAttention(at: date)
        lastInteractionAtByTabID[tabID] = date
        lastAttentionCheckpointAt = date
    }

    func checkpointAttention(at date: Date = .now) {
        defer { lastAttentionCheckpointAt = date }
        guard applicationIsActive,
              webContentIsVisible,
              selectedPageWebSurfaceIsActive,
              let tab = selectedTab,
              !tab.isPrivate,
              let url = tab.url,
              let checkpoint = lastAttentionCheckpointAt,
              date > checkpoint,
              let lastInteraction = lastInteractionAtByTabID[tab.id] else { return }

        let eligibleEnd = min(date, lastInteraction.addingTimeInterval(60))
        guard eligibleEnd > checkpoint else { return }
        appendAttention(
            from: checkpoint,
            to: eligibleEnd,
            tab: tab,
            url: url
        )
    }

    func clearBrowsingInsights() {
        attentionRecords.removeAll()
        mediaUsageRecords.removeAll()
        lastAttentionCheckpointAt = .now
        persist()
    }

    func recordMediaPlayback(_ item: BrowserMediaItem, seconds: TimeInterval, at date: Date = .now) {
        guard seconds > 0, let context = mediaContext(for: item) else { return }
        let siteURL = Self.siteLevelURL(for: context.sourceURL)
        if let lastIndex = mediaUsageRecords.indices.last,
           mediaUsageRecords[lastIndex].sourceURL == siteURL,
           mediaUsageRecords[lastIndex].kind == item.kind,
           Set(mediaUsageRecords[lastIndex].roleIDs) == Set(context.roleIDs),
           date.timeIntervalSince(mediaUsageRecords[lastIndex].endedAt) <= 3 {
            mediaUsageRecords[lastIndex].endedAt = date
            mediaUsageRecords[lastIndex].activeSeconds += seconds
        } else {
            mediaUsageRecords.append(
                BrowserMediaUsageRecord(
                    startedAt: date.addingTimeInterval(-seconds),
                    endedAt: date,
                    sourceURL: siteURL,
                    title: item.title,
                    kind: item.kind,
                    activeSeconds: seconds,
                    roleIDs: context.roleIDs
                )
            )
        }
        pruneBrowsingInsights(relativeTo: date)
        if lastMediaUsagePersistAt == nil
            || date.timeIntervalSince(lastMediaUsagePersistAt ?? .distantPast) >= 30 {
            lastMediaUsagePersistAt = date
            persist()
        }
    }

    private func mediaContext(for item: BrowserMediaItem) -> (sourceURL: URL, roleIDs: [UUID])? {
        if let download = downloads.first(where: { downloadFileURL(for: $0) == item.url }) {
            guard !download.isIncognito else { return nil }
            return (download.sourcePageURL ?? download.sourceURL, download.roleIDs ?? [])
        }
        if let artifactID = item.libraryArtifactID,
           let artifact = libraryArtifacts.first(where: { $0.id == artifactID }) {
            guard !artifact.isIncognito else { return nil }
            if let sourceDownloadID = artifact.sourceDownloadID,
               let download = downloads.first(where: { $0.id == sourceDownloadID }) {
                guard !download.isIncognito else { return nil }
                return (artifact.sourceURL, download.roleIDs ?? [])
            }
            return (artifact.sourceURL, [])
        }
        return nil
    }

    private func startAttentionTimer() {
        guard attentionTask == nil else { return }
        attentionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.checkpointAttention()
            }
        }
    }

    private func appendAttention(from start: Date, to end: Date, tab: BrowserTab, url: URL) {
        let siteURL = Self.siteLevelURL(for: url)
        if let lastIndex = attentionRecords.indices.last,
           attentionRecords[lastIndex].url == siteURL,
           Set(attentionRecords[lastIndex].roleIDs) == Set(tab.roleIDs ?? []),
           start.timeIntervalSince(attentionRecords[lastIndex].endedAt) <= 1 {
            attentionRecords[lastIndex].endedAt = end
            attentionRecords[lastIndex].title = tab.title
            attentionRecords[lastIndex].siteName = tab.siteName
            attentionRecords[lastIndex].faviconURL = tab.faviconURL
        } else {
            attentionRecords.append(
                BrowserAttentionRecord(
                    startedAt: start,
                    endedAt: end,
                    url: siteURL,
                    title: tab.title,
                    siteName: tab.siteName,
                    faviconURL: tab.faviconURL,
                    roleIDs: tab.roleIDs ?? []
                )
            )
        }
        pruneBrowsingInsights(relativeTo: end)
        if lastAttentionPersistAt == nil
            || end.timeIntervalSince(lastAttentionPersistAt ?? .distantPast) >= 60 {
            lastAttentionPersistAt = end
            persist()
        }
    }

    private func pruneBrowsingInsights(relativeTo date: Date) {
        let cutoff = Self.insightsCutoff(relativeTo: date)
        attentionRecords.removeAll { $0.endedAt < cutoff }
        mediaUsageRecords.removeAll { $0.endedAt < cutoff }
    }

    private static func insightsCutoff(relativeTo date: Date) -> Date {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: -90, to: date) ?? .distantPast
    }

    private static func siteLevelURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil else { return url }
        components.user = nil
        components.password = nil
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    private func recordNavigation(
        tabID: UUID,
        url: URL,
        title: String,
        metadata: PageVisualMetadata
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        if tabID == selectedTabID { checkpointAttention(at: .now) }
        let resolvedPopup = popupParentTabIDs.removeValue(forKey: tabID) != nil
        tabs[index].url = url
        tabs[index].title = title
        tabs[index].siteName = metadata.siteName
        tabs[index].faviconURL = metadata.faviconURL ?? URLResolver.conventionalFaviconURL(for: url)
        tabs[index].previewImageURL = metadata.previewImageURL
        if !tabs[index].isPrivate, let snapshotJPEGData = metadata.snapshotJPEGData {
            let filename = "\(tabID.uuidString).jpg"
            do {
                try FileManager.default.createDirectory(at: tabPreviewDirectory, withIntermediateDirectories: true)
                try snapshotJPEGData.write(
                    to: tabPreviewDirectory.appendingPathComponent(filename, isDirectory: false),
                    options: .atomic
                )
                tabs[index].snapshotFilename = filename
            } catch {
                persistenceError = "Tab preview could not be saved: \(error.localizedDescription)"
            }
        }
        tabs[index].lastActiveAt = .now

        if resolvedPopup {
            selectedTabID = tabID
        }

        let tab = tabs[index]
        if tabID == selectedTabID, !tab.isPrivate, let identityID = tab.identityID {
            if history.first?.url != url
                || history.first?.identityID != identityID
                || Set(history.first?.roleIDs ?? []) != Set(tab.roleIDs ?? []) {
                history.insert(
                    BrowserHistoryEntry(
                        identityID: identityID,
                        url: url,
                        title: title,
                        siteName: metadata.siteName,
                        faviconURL: metadata.faviconURL ?? URLResolver.conventionalFaviconURL(for: url),
                        roleIDs: tab.roleIDs ?? []
                    ),
                    at: 0
                )
                history = Array(history.prefix(2_000))
            }
        }
        persist()
    }

    private func updateRecentHistoryRoleContext(for tab: BrowserTab) {
        guard !tab.isPrivate,
              let identityID = tab.identityID,
              let url = tab.url,
              let historyIndex = history.firstIndex(where: {
                  $0.identityID == identityID && $0.url == url
              }) else { return }
        history[historyIndex].roleIDs = tab.roleIDs ?? []
    }

    private func detachDownloadOnlyPopup(tabID: UUID, downloadID: UUID) {
        guard let parentTabID = popupParentTabIDs.removeValue(forKey: tabID),
              let page = pages.removeValue(forKey: tabID) else { return }

        detachedDownloadPages[downloadID] = page
        tabs.removeAll(where: { $0.id == tabID })

        if selectedTabID == tabID || selectedTabID == nil {
            selectedTabID = tabs.contains(where: { $0.id == parentTabID })
                ? parentTabID
                : tabs.max(by: { $0.lastActiveAt < $1.lastActiveAt })?.id
        }

        if tabs.isEmpty {
            createTab()
        } else {
            persist()
        }
    }

    func recordDownloadStarted(_ record: BrowserDownloadRecord) {
        if let previous = downloads.first(where: { $0.id == record.id }) {
            clearResumeData(for: previous)
        }
        downloads.removeAll(where: { $0.id == record.id })
        downloads.insert(record, at: 0)
        persist()
        showDownloadNotice(
            "Downloading \(record.fileName)",
            systemImage: "arrow.down.circle"
        )
    }

    func updateDownload(id: UUID, progress: Double) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].progress = min(max(progress, 0), 1)
    }

    func finishDownload(id: UUID, byteCount: Int64? = nil, completedAt: Date = .now) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let fileName = downloads[index].fileName
        downloads[index].progress = 1
        downloads[index].state = .completed
        downloads[index].errorDescription = nil
        downloads[index].fileByteCount = byteCount
        downloads[index].completedAt = completedAt
        clearResumeData(for: downloads[index])
        downloads[index].resumeDataFilename = nil
        persist()
        showDownloadNotice(
            "Downloaded \(fileName)",
            systemImage: "checkmark.circle.fill"
        )
    }

    func failDownload(
        id: UUID,
        message: String,
        cancelled: Bool,
        resumeData: Data? = nil
    ) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[index].state = cancelled ? .cancelled : .failed
        downloads[index].errorDescription = cancelled ? nil : message
        if let resumeData {
            if downloads[index].isIncognito {
                incognitoResumeData[id] = resumeData
            } else if let filename = try? BrowserDownloadSupport.saveResumeData(
                resumeData,
                downloadID: id,
                directory: resumeDataDirectory
            ) {
                downloads[index].resumeDataFilename = filename
            }
        }
        persist()
        showDownloadNotice(
            cancelled ? "Download cancelled" : "Download failed",
            systemImage: cancelled ? "xmark.circle" : "exclamationmark.triangle.fill",
            isFailure: !cancelled
        )
    }

    func showNotice(
        _ message: String,
        systemImage: String,
        isFailure: Bool = false
    ) {
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

    private func showDownloadNotice(
        _ message: String,
        systemImage: String,
        isFailure: Bool = false
    ) {
        showNotice(message, systemImage: systemImage, isFailure: isFailure)
    }

    private func clearResumeData(for record: BrowserDownloadRecord) {
        incognitoResumeData[record.id] = nil
        BrowserDownloadSupport.removeResumeData(
            filename: record.resumeDataFilename,
            directory: resumeDataDirectory
        )
    }

    private func persist() {
        let persistentTabs = tabs.filter { !$0.isPrivate && !$0.isUncommittedBlank }
        let persistentSelectedID = persistentTabs.contains(where: { $0.id == selectedTabID })
            ? selectedTabID
            : persistentTabs.first?.id
        let snapshot = BrowserSnapshot(
            identities: identities,
            roles: roles,
            tabs: persistentTabs,
            selectedTabID: persistentSelectedID,
            history: history,
            bookmarks: bookmarks,
            savedBookmarkLists: savedBookmarkLists,
            readingList: readingList,
            downloads: downloads.filter { !$0.isIncognito },
            libraryArtifacts: libraryArtifacts,
            attentionRecords: attentionRecords,
            mediaUsageRecords: mediaUsageRecords
        )
        do {
            try persistence.save(snapshot)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private static let legacyDefaultRoleKeys: Set<String> = ["personal"]
}

enum LibraryArtifactError: LocalizedError {
    case fileUnavailable

    var errorDescription: String? {
        switch self {
        case .fileUnavailable: "The downloaded file is no longer available."
        }
    }
}
