import SwiftUI
import UIKit
import QuickLook
import QuickLookThumbnailing

struct TabOverviewView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var mediaPlayback: BrowserMediaPlaybackController
    @EnvironmentObject private var documentViewer: BrowserDocumentViewerController
    @EnvironmentObject private var transcription: BrowserTranscriptionController
    let sourceTabID: UUID?
    let onDone: () -> Void
    let onShowReadingList: () -> Void
    @State private var section: TabOverviewSection = .tabs
    @State private var selectedRoleIDs: Set<UUID> = []
    @State private var roleOrderIDs: [UUID] = []
    @State private var roleSelectorWidth: CGFloat = 320
    @State private var rolesExpanded = false
    @State private var newTabIsPrivate = false
    @State private var didInitializeNewTabContext = false
    @State private var previewedDownloadURL: URL?
    @State private var editingBookmark: Bookmark?
    @State private var selectedSavedListID: UUID?
    @State private var requestedFocusTabID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch section {
                    case .tabs: tabsGrid
                    case .bookmarks: bookmarksList
                    case .history: historyList
                    case .downloads: downloadsList
                    case .readingList: Color.clear
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footerControls
            }
            .background(workspaceBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(workspaceBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(newTabIsPrivate ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDone) {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back to browser")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if section == .tabs {
                        Button(action: startNewTab) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(newTabIsPrivate ? "New Incognito Tab" : "New Tab")
                    }

                    incognitoButton
                }
            }
            .onAppear {
                initializeNewTabContext()
                store.prepareMissingTabVisuals()
                DispatchQueue.main.async {
                    requestedFocusTabID = sourceTabID
                }
            }
            .quickLookPreview($previewedDownloadURL)
            .sheet(item: $editingBookmark) { bookmark in
                SavedBookmarkEditorView(bookmark: bookmark)
                    .environmentObject(store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .background(workspaceBackground.ignoresSafeArea())
        .preferredColorScheme(newTabIsPrivate ? .dark : .light)
        .environment(\.colorScheme, newTabIsPrivate ? .dark : .light)
    }

    private var footerControls: some View {
        VStack(spacing: 8) {
            if !pinnedDockTabs.isEmpty {
                pinnedTabDock
            }

            roleFooter

            sectionSelector
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: workspaceBackground.opacity(newTabIsPrivate ? 0.22 : 0.16), location: 0),
                    .init(color: workspaceBackground.opacity(newTabIsPrivate ? 0.78 : 0.72), location: 0.3),
                    .init(color: workspaceBackground.opacity(newTabIsPrivate ? 0.98 : 0.96), location: 0.58),
                    .init(color: workspaceBackground, location: 1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, footerGradientTopPadding)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeInOut(duration: 0.18), value: section)
    }

    private var pinnedTabDock: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: PinnedTabDockPresentation.iconSpacing) {
                    ForEach(pinnedDockTabs) { tab in
                        Button {
                            store.selectTab(tab.id)
                            onDone()
                        } label: {
                            PinnedTabIconArtwork(
                                tab: tab,
                                isSelected: tab.id == store.selectedTab?.id
                            )
                            .frame(width: PinnedTabDockPresentation.itemWidth)
                            .frame(minHeight: PinnedTabDockPresentation.height)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open pinned tab (tab.title)")
                        .accessibilityValue(tab.id == store.selectedTab?.id ? "Current tab" : "Pinned tab")
                    }
                }
                .frame(minWidth: proxy.size.width, alignment: .center)
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)
        }
        .frame(height: PinnedTabDockPresentation.height)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pinned tabs")
    }

    private var roleFooter: some View {
        Group {
            if !store.activeRoles.isEmpty {
                roleFilters
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(
                        Color.clear,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sectionSelector: some View {
        HStack(spacing: 4) {
            ForEach(TabOverviewSection.allCases) { destination in
                let isSelected = section == destination
                Button {
                    if destination == .readingList {
                        onShowReadingList()
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            section = destination
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: destination.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(destination.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(
                        isSelected
                            ? (newTabIsPrivate ? Color.white : Color.browserAccent)
                            : secondaryText
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        isSelected
                            ? (newTabIsPrivate ? Color.white.opacity(0.12) : Color.browserAccent.opacity(0.1))
                            : Color.clear,
                        in: Capsule()
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(
                newTabIsPrivate ? Color.white.opacity(0.12) : Color.browserInk.opacity(0.08)
            )
        }
    }

    private var tabsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: TabCardLayout.columns, spacing: TabCardLayout.gridSpacing) {
                        ForEach(filteredTabs) { tab in
                            tabCard(tab)
                                .id(tab.id)
                        }
                    }

                    if filteredTabs.isEmpty {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                emptyTabsTitle,
                                systemImage: newTabIsPrivate ? "eye.slash" : "square.on.square",
                                description: Text(emptyTabsDescription)
                            )

                            if newTabIsPrivate {
                                Button(action: startNewTab) {
                                    Label("Start Incognito", systemImage: "plus")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.incognitoCanvas)
                                        .padding(.horizontal, 18)
                                        .frame(minHeight: 44)
                                        .background(Color.white, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .foregroundStyle(primaryText)
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .onChange(of: requestedFocusTabID) { _, requestedID in
                guard let targetID = TabOverviewInitialFocus.targetID(
                    sourceTabID: requestedID,
                    visibleTabs: filteredTabs
                ) else { return }
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }

    private var roleFilters: some View {
        let rows = RoleChipLayout.rows(
            roles: orderedRoles,
            availableWidth: max(
                44,
                roleSelectorWidth - RoleChipLayout.indicatorWidth - 6
            )
        )
        let visibleRows = rolesExpanded ? rows : Array(rows.prefix(2))

        return VStack(spacing: RoleChipLayout.verticalSpacing) {
            ForEach(Array(visibleRows.enumerated()), id: \.offset) { index, roles in
                HStack(spacing: RoleChipLayout.horizontalSpacing) {
                    if index == 0 {
                        Image("RolesIcon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 17, height: 17)
                            .foregroundStyle(secondaryText)
                            .frame(width: RoleChipLayout.indicatorWidth, height: RoleChipLayout.rowHeight)
                            .accessibilityHidden(true)
                    }

                    ForEach(roles) { role in
                        roleChip(role)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: RoleChipLayout.rowHeight, alignment: .center)
            }

            if rows.count > 2 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        rolesExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(rolesExpanded ? "Show less" : "Show all roles")
                        Image(systemName: rolesExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(secondaryText)
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .accessibilityValue(rolesExpanded ? "Expanded" : "Collapsed")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RoleSelectorWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(RoleSelectorWidthPreferenceKey.self) { width in
            if width > 0 { roleSelectorWidth = width }
        }
    }

    private var bookmarksList: some View {
        let roleFilteredBookmarks = store.bookmarks(
            incognitoOnly: newTabIsPrivate,
            matchingRoleIDs: selectedRoleIDs
        )
        let activeSelectedSavedListID = selectedSavedListID.flatMap { savedListID in
            visibleSavedLists.contains(where: { $0.id == savedListID }) ? savedListID : nil
        }
        let visibleBookmarks = activeSelectedSavedListID.map { savedListID in
            roleFilteredBookmarks.filter { ($0.savedListIDs ?? []).contains(savedListID) }
        } ?? roleFilteredBookmarks
        let sections = BrowserLibraryGrouping.bookmarkSections(for: visibleBookmarks)

        return VStack(spacing: 0) {
            if !visibleSavedLists.isEmpty {
                savedListFilter
            }

            Group {
                if visibleBookmarks.isEmpty {
                    ContentUnavailableView(
                        bookmarkEmptyTitle,
                        systemImage: newTabIsPrivate ? "eye.slash" : "bookmark",
                        description: Text(bookmarkEmptyDescription)
                    )
                } else {
                    List {
                    ForEach(sections) { daySection in
                        Section(daySection.title) {
                            ForEach(daySection.bookmarks) { bookmark in
                                HStack(alignment: .top, spacing: 4) {
                                    Button {
                                        store.open(bookmark)
                                        onDone()
                                    } label: {
                                        bookmarkRow(bookmark)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        editingBookmark = bookmark
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 16, weight: .semibold))
                                            .rotationEffect(.degrees(90))
                                            .foregroundStyle(primaryText)
                                            .frame(width: 36, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Options for \(bookmark.title)")
                                }
                            }
                        }
                    }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private var savedListFilter: some View {
        Menu {
            Button {
                selectedSavedListID = nil
            } label: {
                if selectedSavedListID == nil {
                    Label("All Saved", systemImage: "checkmark")
                } else {
                    Text("All Saved")
                }
            }

            ForEach(visibleSavedLists) { list in
                Button {
                    selectedSavedListID = list.id
                } label: {
                    if selectedSavedListID == list.id {
                        Label(list.name, systemImage: "checkmark")
                    } else {
                        Text(list.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                Text(selectedSavedListName)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var selectedSavedListName: String {
        guard let selectedSavedListID,
              let list = visibleSavedLists.first(where: { $0.id == selectedSavedListID }) else {
            return "All Saved"
        }
        return list.name
    }

    private var visibleSavedLists: [SavedBookmarkList] {
        store.savedBookmarkLists(incognitoOnly: newTabIsPrivate)
    }

    private var historyList: some View {
        let visibleHistory = store.history(
            incognitoOnly: newTabIsPrivate,
            matchingRoleIDs: selectedRoleIDs
        )
        let sections = BrowserLibraryGrouping.historySections(for: visibleHistory)

        return Group {
            if visibleHistory.isEmpty {
                ContentUnavailableView(
                    historyEmptyTitle,
                    systemImage: newTabIsPrivate ? "eye.slash" : "clock",
                    description: Text(historyEmptyDescription)
                )
            } else {
                List {
                    ForEach(sections) { daySection in
                        Section(daySection.title) {
                            ForEach(daySection.entries) { entry in
                                Button {
                                    store.open(entry.url, preferredIdentityID: entry.identityID)
                                    onDone()
                                } label: {
                                    historyRow(entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var downloadsList: some View {
        let visibleDownloads = store.downloads(
            incognitoOnly: newTabIsPrivate,
            matchingRoleIDs: selectedRoleIDs
        )
        let sections = BrowserDownloadGrouping.sections(for: visibleDownloads)

        return Group {
            if visibleDownloads.isEmpty {
                ContentUnavailableView(
                    downloadEmptyTitle,
                    systemImage: "arrow.down.circle",
                    description: Text(downloadEmptyDescription)
                )
            } else {
                List {
                    ForEach(sections) { daySection in
                        Section(daySection.title) {
                            ForEach(daySection.downloads) { download in
                                downloadRow(download)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            store.removeDownload(download.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func downloadRow(_ download: BrowserDownloadRecord) -> some View {
        let fileURL = store.downloadFileURL(for: download)
        let canRetry = download.state == .failed
            || download.state == .cancelled
            || (download.state == .completed && fileURL == nil)

        return HStack(alignment: .top, spacing: 12) {
            DownloadFileVisual(
                download: download,
                fileURL: fileURL,
                tint: downloadColor(for: download.state),
                usesDarkBackground: newTabIsPrivate
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(download.fileName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Text(downloadMetadata(download))
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)

                downloadSourceLine(download)

                if download.state == .downloading {
                    ProgressView(value: download.progress)
                        .tint(newTabIsPrivate ? Color.white : Color.browserAccent)
                } else if let status = downloadStatus(download, fileURL: fileURL) {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(download.state == .failed ? Color.red : secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            downloadActionsMenu(download, fileURL: fileURL, canRetry: canRetry)
                .alignmentGuide(.top) { $0[.top] }
        }
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .onTapGesture {
            guard download.state == .completed else { return }
            openDownloadedFile(download, fileURL: fileURL)
        }
    }

    private func downloadActionsMenu(
        _ download: BrowserDownloadRecord,
        fileURL: URL?,
        canRetry: Bool
    ) -> some View {
        Menu {
            if download.state == .completed, let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                if BrowserDownloadSupport.mediaKind(for: download) != nil {
                    Button {
                        openDownloadedFile(download, fileURL: fileURL)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                } else if !BrowserDownloadSupport.isPDF(download) {
                    Button {
                        previewedDownloadURL = fileURL
                    } label: {
                        Label("Preview", systemImage: "doc.text.magnifyingglass")
                    }
                } else {
                    Button {
                        documentViewer.presentPDF(url: fileURL, title: download.fileName)
                        onDone()
                    } label: {
                        Label("Open PDF", systemImage: "doc.richtext")
                    }
                }

                if let artifact = store.libraryArtifact(for: download) {
                    if artifact.isArchived {
                        Button {
                            store.setLibraryArtifactArchived(artifact.id, archived: false)
                        } label: {
                            Label("Restore to Library", systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button {
                            store.removeLibraryArtifact(artifact.id)
                        } label: {
                            Label("Remove from Library", systemImage: "books.vertical")
                        }
                    }
                } else {
                    Button {
                        addToLibrary(download)
                    } label: {
                        Label("Add to Library", systemImage: "books.vertical.fill")
                    }
                }

                if BrowserDownloadSupport.mediaKind(for: download) != nil {
                    Button {
                        transcribe(download)
                    } label: {
                        Label("Transcribe Audio", systemImage: "waveform.and.magnifyingglass")
                    }
                    .disabled(transcription.activeArtifactID != nil)
                }
            }

            if download.state == .downloading {
                Button {
                    store.cancelDownload(download.id)
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            } else if canRetry {
                Button {
                    store.retryDownload(download.id)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
            }

            Divider()

            Button(role: .destructive) {
                store.removeDownload(download.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .rotationEffect(.degrees(90))
                .foregroundStyle(primaryText)
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel("Options for \(download.fileName)")
    }

    private func tabCard(_ tab: BrowserTab) -> some View {
        let usesDarkCard = newTabIsPrivate || tab.isPrivate

        return GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Button {
                    store.selectTab(tab.id)
                    onDone()
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        tabPreview(tab)
                            .frame(
                                width: geometry.size.width - TabCardLayout.closeOverlapInset,
                                height: TabCardLayout.previewHeight
                            )
                            .clipped()

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                tabFavicon(tab, size: 18)

                                Text(tab.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(usesDarkCard ? Color.white : Color.browserInk)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer(minLength: 0)
                            }

                            Spacer(minLength: 0)
                            tabRoleBadges(tab, usesDarkCard: usesDarkCard)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clipped()
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(
                        width: geometry.size.width - TabCardLayout.closeOverlapInset,
                        height: TabCardLayout.contentHeight,
                        alignment: .topLeading
                    )
                    .background(
                        usesDarkCard ? Color.incognitoSurface : Color.white,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                tab.id == store.selectedTabID
                                    ? (usesDarkCard ? Color.white.opacity(0.55) : Color.browserAccent.opacity(0.5))
                                    : (usesDarkCard ? Color.white.opacity(0.1) : Color.browserInk.opacity(0.06)),
                                lineWidth: tab.id == store.selectedTabID ? 1.5 : 1
                            )
                    }
                    .shadow(color: Color.browserInk.opacity(0.06), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .contextMenu {
                    if !tab.isPrivate {
                        Button {
                            store.togglePinned(tab.id)
                        } label: {
                            Label(tab.isPinned ? "Unpin Tab" : "Pin Tab", systemImage: tab.isPinned ? "pin.slash" : "pin")
                        }
                    }

                    if !tab.isPinned {
                        Button(role: .destructive) {
                            store.closeTab(tab.id)
                        } label: {
                            Label("Close Tab", systemImage: "xmark")
                        }
                    }
                }

                Button {
                    if tab.isPinned {
                        store.togglePinned(tab.id)
                    } else {
                        store.closeTab(tab.id)
                    }
                } label: {
                    Image(systemName: tab.isPinned ? "pin.fill" : "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(usesDarkCard ? Color.white : Color.browserInk.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(Color.white.opacity(usesDarkCard ? 0.28 : 0.8))
                        }
                        .shadow(color: Color.browserInk.opacity(0.16), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.isPinned ? "Unpin \(tab.title)" : "Close \(tab.title)")
            }
            .frame(width: geometry.size.width, height: TabCardLayout.outerHeight)
        }
        .frame(height: TabCardLayout.outerHeight)
    }

    @ViewBuilder
    private func tabPreview(_ tab: BrowserTab) -> some View {
        if let previewImageURL = tab.previewImageURL {
            AsyncImage(url: previewImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    tabPreviewFallback(tab)
                }
            }
        } else {
            tabPreviewFallback(tab)
        }
    }

    private func tabPreviewFallback(_ tab: BrowserTab) -> some View {
        Group {
            if let snapshotURL = store.snapshotURL(for: tab),
               let image = UIImage(contentsOfFile: snapshotURL.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [siteTint(tab).opacity(0.22), Color.browserCanvas],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    tabFavicon(tab, size: 34)
                }
            }
        }
    }

    @ViewBuilder
    private func tabFavicon(_ tab: BrowserTab, size: CGFloat) -> some View {
        if let faviconURL = tab.faviconURL ?? URLResolver.conventionalFaviconURL(for: tab.url) {
            AsyncImage(url: faviconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    faviconFallback(tab)
                }
            }
            .frame(width: size, height: size)
            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else {
            faviconFallback(tab)
                .frame(width: size, height: size)
        }
    }

    private func faviconFallback(_ tab: BrowserTab) -> some View {
        Image(systemName: tab.url == nil ? "plus" : "globe")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(siteTint(tab))
    }

    private func siteTint(_ tab: BrowserTab) -> Color {
        guard let host = tab.url?.host else { return Color.browserAccent }
        let palette = ["00A88F", "087E99", "5969D9", "B15B91", "D2772B", "557A46"]
        let index = host.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return Color(hex: palette[index])
    }

    @ViewBuilder
    private func tabRoleBadges(_ tab: BrowserTab, usesDarkCard: Bool) -> some View {
        let selectedIDs = Set(tab.roleIDs ?? [])
        let selectedRoles = store.activeRoles.filter { selectedIDs.contains($0.id) }

        if !selectedRoles.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(selectedRoles.prefix(2))) { role in
                    Text(role.name)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(usesDarkCard ? Color.white : Color.browserInk.opacity(0.78))
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(
                            usesDarkCard ? Color.white.opacity(0.2) : Color.browserInk.opacity(0.09),
                            in: Capsule()
                        )
                        .frame(maxWidth: 72)
                }

                if selectedRoles.count > 2 {
                    Text("+\(selectedRoles.count - 2)")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(usesDarkCard ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
        }
    }

    private var filteredTabs: [BrowserTab] {
        store.tabs(
            matchingRoleIDs: selectedRoleIDs,
            incognitoOnly: newTabIsPrivate
        )
    }

    private var pinnedDockTabs: [BrowserTab] {
        PinnedTabDockPresentation.tabs(
            from: store.pinnedTabs,
            showsTabsSection: section == .tabs,
            isPrivate: newTabIsPrivate
        )
    }

    private var footerGradientTopPadding: CGFloat {
        pinnedDockTabs.isEmpty ? -56 : 24
    }

    private var emptyTabsTitle: String {
        if newTabIsPrivate { return "No Incognito tabs" }
        return selectedRoleIDs.isEmpty ? "No open tabs" : "No matching tabs"
    }

    private var emptyTabsDescription: String {
        if newTabIsPrivate { return "Start a private tab that will not be restored after this session." }
        return selectedRoleIDs.isEmpty
            ? "Use the New Tab button in the browser footer to begin browsing."
            : "Select fewer Roles or clear the Role selection to show all tabs."
    }

    private func startNewTab() {
        let context = TabOverviewInitialContext.resolve(
            selectedTab: store.selectedTab,
            fallbackIdentityID: store.identities.first?.id
        )
        let tab = store.createTab(
            identityID: newTabIsPrivate ? nil : context.identityID,
            roleIDs: Array(selectedRoleIDs),
            isPrivate: newTabIsPrivate
        )
        _ = store.page(for: tab)
        onDone()
    }

    private var bookmarkEmptyTitle: String {
        if !selectedRoleIDs.isEmpty {
            return newTabIsPrivate ? "No matching Incognito Saved Bookmarks" : "No matching Saved Bookmarks"
        }
        return newTabIsPrivate ? "No Incognito Saved Bookmarks" : "No Saved Bookmarks"
    }

    private var bookmarkEmptyDescription: String {
        if !selectedRoleIDs.isEmpty { return "No saved pages use the selected Roles." }
        return newTabIsPrivate
            ? "Pages you explicitly save in Incognito appear here and remain after the session ends."
            : "Save pages from the Main Menu."
    }

    private var historyEmptyTitle: String {
        if newTabIsPrivate { return "No Incognito history" }
        return selectedRoleIDs.isEmpty ? "No history" : "No matching history"
    }

    private var historyEmptyDescription: String {
        if newTabIsPrivate { return "Incognito browsing is never added to History." }
        return selectedRoleIDs.isEmpty
            ? "Normal browsing appears here. Incognito activity never does."
            : "No History entries use the selected Roles."
    }

    private var downloadEmptyTitle: String {
        if !selectedRoleIDs.isEmpty { return newTabIsPrivate ? "No matching Incognito downloads" : "No matching downloads" }
        return newTabIsPrivate ? "No Incognito downloads" : "No downloads"
    }

    private var downloadEmptyDescription: String {
        if !selectedRoleIDs.isEmpty { return "No downloads use the selected Roles." }
        return newTabIsPrivate
            ? "Files downloaded in Incognito remain explicit local files but are not retained in normal download history."
            : "Files downloaded from webpages appear here and in Browser’s Downloads folder in Files."
    }

    private var navigationTitle: String {
        section.navigationTitle(isIncognito: newTabIsPrivate)
    }

    private var incognitoButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                togglePrivateMode()
            }
        } label: {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(newTabIsPrivate ? Color.white : primaryText)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(newTabIsPrivate ? "Turn off Incognito" : "Use Incognito")
        .accessibilityValue(newTabIsPrivate ? "On" : "Off")
    }

    private func initializeNewTabContext() {
        guard !didInitializeNewTabContext else { return }
        didInitializeNewTabContext = true
        let context = TabOverviewInitialContext.resolve(
            selectedTab: store.selectedTab,
            fallbackIdentityID: store.identities.first?.id
        )
        newTabIsPrivate = context.isPrivate
        selectedRoleIDs = context.roleIDs
        roleOrderIDs = store.rolesByUsage(prioritizing: context.roleIDs).map(\.id)
        rolesExpanded = false
    }

    private func roleChip(_ role: BrowserRole) -> some View {
        let isSelected = selectedRoleIDs.contains(role.id)

        return Text(role.name)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(roleChipForeground(isSelected: isSelected))
            .padding(.horizontal, RoleChipLayout.horizontalPadding)
            .frame(height: RoleChipLayout.visualHeight)
            .background(roleChipBackground(isSelected: isSelected), in: Capsule())
            .frame(minWidth: 44, minHeight: RoleChipLayout.rowHeight)
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded {
                    toggleRoleSelection(role)
                }
            )
            .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(role.name) role")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction {
            toggleRoleSelection(role)
        }
    }

    private func toggleRoleSelection(_ role: BrowserRole) {
        let wasSelected = selectedRoleIDs.contains(role.id)
        selectedRoleIDs = RoleSelection.toggled(role.id, in: selectedRoleIDs)
        if !wasSelected {
            store.recordRoleUsage([role.id])
        }
    }

    private var orderedRoles: [BrowserRole] {
        let rolesByID = Dictionary(uniqueKeysWithValues: store.activeRoles.map { ($0.id, $0) })
        let ordered = roleOrderIDs.compactMap { rolesByID[$0] }
        let knownIDs = Set(ordered.map(\.id))
        return ordered + store.activeRoles.filter { !knownIDs.contains($0.id) }
    }

    private func roleChipForeground(isSelected: Bool) -> Color {
        if newTabIsPrivate {
            return isSelected ? .white : Color.white.opacity(0.72)
        }
        return isSelected ? .white : Color.browserInk.opacity(0.76)
    }

    private func roleChipBackground(isSelected: Bool) -> Color {
        if newTabIsPrivate {
            return Color.white.opacity(isSelected ? 0.28 : 0.09)
        }
        return Color.browserInk.opacity(isSelected ? 0.86 : 0.08)
    }

    private func togglePrivateMode() {
        newTabIsPrivate.toggle()
    }

    private var workspaceBackground: Color {
        newTabIsPrivate ? .incognitoCanvas : .browserCanvas
    }

    private var primaryText: Color {
        newTabIsPrivate ? .white : .browserInk
    }

    private var secondaryText: Color {
        newTabIsPrivate ? Color.white.opacity(0.62) : .secondary
    }

    private func downloadColor(for state: BrowserDownloadState) -> Color {
        switch state {
        case .downloading, .completed: newTabIsPrivate ? .white : .browserAccent
        case .failed: .red
        case .cancelled: secondaryText
        }
    }

    private func downloadMetadata(_ download: BrowserDownloadRecord) -> String {
        let type = BrowserDownloadSupport.typeDescription(for: download)
        let byteCount: Int64?
        if download.state == .downloading, let expected = download.expectedByteCount {
            byteCount = Int64(Double(expected) * download.progress)
        } else {
            byteCount = download.fileByteCount ?? download.expectedByteCount
        }
        guard let size = BrowserDownloadSupport.byteCountDescription(byteCount) else { return type }
        if download.state == .downloading,
           let total = BrowserDownloadSupport.byteCountDescription(download.expectedByteCount) {
            return "\(type) • \(size) of \(total)"
        }
        return "\(type) • \(size)"
    }

    @ViewBuilder
    private func downloadSourceLine(_ download: BrowserDownloadRecord) -> some View {
        let pageURL = download.sourcePageURL ?? download.sourceURL
        let host = pageURL.host ?? download.sourceURL.host ?? download.sourceURL.absoluteString
        let date = download.completedAt ?? download.createdAt
        HStack(spacing: 5) {
            DownloadSourceFavicon(
                url: download.sourceFaviconURL ?? URLResolver.conventionalFaviconURL(for: pageURL),
                tint: secondaryText
            )
            Text("\(host) • \(date.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(secondaryText)
                .lineLimit(1)
        }
    }

    private func downloadStatus(_ download: BrowserDownloadRecord, fileURL: URL?) -> String? {
        switch download.state {
        case .downloading:
            return "Downloading • \(Int(download.progress * 100))%"
        case .completed:
            return fileURL == nil ? "File removed — download again" : nil
        case .failed:
            return download.errorDescription ?? "Download failed"
        case .cancelled:
            return "Cancelled — ready to retry"
        }
    }

    private func openDownloadedFile(_ download: BrowserDownloadRecord, fileURL: URL?) {
        guard let fileURL else { return }
        if BrowserDownloadSupport.isPDF(download) {
            documentViewer.presentPDF(url: fileURL, title: download.fileName)
            onDone()
            return
        }
        guard let kind = BrowserDownloadSupport.mediaKind(for: download) else {
            previewedDownloadURL = fileURL
            return
        }
        mediaPlayback.play(
            url: fileURL,
            title: download.fileName,
            kind: kind,
            libraryArtifactID: store.libraryArtifact(for: download)?.id
        )
        onDone()
    }

    private func addToLibrary(_ download: BrowserDownloadRecord) {
        do {
            _ = try store.addDownloadToLibrary(download)
        } catch {
            store.showNotice(
                error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                isFailure: true
            )
        }
    }

    private func transcribe(_ download: BrowserDownloadRecord) {
        do {
            let artifact = try store.addDownloadToLibrary(download)
            guard let url = store.libraryFileURL(for: artifact) else { return }
            transcription.transcribe(artifact: artifact, url: url, store: store)
        } catch {
            store.showNotice(
                error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                isFailure: true
            )
        }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        destinationRow(
            title: bookmark.title,
            siteName: bookmark.siteName,
            url: bookmark.url,
            faviconURL: bookmark.faviconURL,
            date: bookmark.createdAt,
            datePrefix: "Saved",
            note: bookmark.note
        )
    }

    private func historyRow(_ entry: BrowserHistoryEntry) -> some View {
        destinationRow(
            title: entry.title,
            siteName: entry.siteName,
            url: entry.url,
            faviconURL: entry.faviconURL,
            date: entry.visitedAt,
            datePrefix: nil,
            note: nil
        )
    }

    private func destinationRow(
        title: String,
        siteName: String?,
        url: URL,
        faviconURL: URL?,
        date: Date,
        datePrefix: String?,
        note: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            WebsiteListFavicon(
                url: faviconURL ?? URLResolver.conventionalFaviconURL(for: url),
                tint: newTabIsPrivate ? .white : .browserAccent,
                usesDarkBackground: newTabIsPrivate
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    if datePrefix == nil {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(secondaryText.opacity(0.9))
                            .fixedSize()
                    }
                }

                Text(destinationSource(siteName: siteName, url: url))
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)

                if let note,
                   !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(primaryText.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let datePrefix {
                    Text("\(datePrefix) \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(secondaryText.opacity(0.9))
                }
            }

            Spacer()
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private func destinationSource(siteName: String?, url: URL) -> String {
        let host = url.host ?? url.absoluteString
        guard let siteName = siteName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !siteName.isEmpty,
              siteName.caseInsensitiveCompare(host) != .orderedSame else {
            return host
        }
        return "\(siteName) · \(host)"
    }

}

private struct DownloadFileVisual: View {
    let download: BrowserDownloadRecord
    let fileURL: URL?
    let tint: Color
    let usesDarkBackground: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(usesDarkBackground ? Color.white.opacity(0.08) : Color.browserInk.opacity(0.05))

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else if BrowserDownloadSupport.isPDF(download) {
                VStack(spacing: 2) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 19, weight: .medium))
                    Text("PDF")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.red)
            } else {
                Image(systemName: BrowserDownloadSupport.systemImage(for: download))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
            }

            if thumbnail != nil, BrowserDownloadSupport.isPDF(download) {
                Text("PDF")
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .frame(height: 12)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(3)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(usesDarkBackground ? Color.white.opacity(0.12) : Color.browserInk.opacity(0.08))
        }
        .task(id: fileURL) {
            thumbnail = await loadThumbnail()
        }
        .accessibilityHidden(true)
    }

    private func loadThumbnail() async -> UIImage? {
        guard download.state == .completed, let fileURL else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 104, height: 104),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
    }
}

private struct DownloadSourceFavicon: View {
    let url: URL?
    let tint: Color

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
    }
}

private struct WebsiteListFavicon: View {
    let url: URL?
    let tint: Color
    let usesDarkBackground: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(usesDarkBackground ? Color.white.opacity(0.09) : Color.browserInk.opacity(0.05))

            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(7)
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
    }
}

struct RoleChipLayout {
    static let indicatorWidth: CGFloat = 24
    static let horizontalPadding: CGFloat = 8
    static let horizontalSpacing: CGFloat = 4
    static let verticalSpacing: CGFloat = 0
    static let visualHeight: CGFloat = 22
    static let rowHeight: CGFloat = 32
    static let maximumWidth: CGFloat = 144

    static func rows(
        roles: [BrowserRole],
        availableWidth: CGFloat
    ) -> [[BrowserRole]] {
        rows(items: roles, availableWidth: availableWidth) { role in
            measuredWidth(for: role.name)
        }
    }

    static func rows<Item>(
        items: [Item],
        availableWidth: CGFloat,
        width: (Item) -> CGFloat
    ) -> [[Item]] {
        guard !items.isEmpty else { return [] }
        let availableWidth = max(44, availableWidth)
        var rows: [[Item]] = []
        var currentRow: [Item] = []
        var occupiedWidth: CGFloat = 0

        for item in items {
            let itemWidth = min(max(44, width(item)), availableWidth)
            let proposedWidth = currentRow.isEmpty
                ? itemWidth
                : occupiedWidth + horizontalSpacing + itemWidth
            if !currentRow.isEmpty, proposedWidth > availableWidth {
                rows.append(currentRow)
                currentRow = [item]
                occupiedWidth = itemWidth
            } else {
                currentRow.append(item)
                occupiedWidth = proposedWidth
            }
        }

        if !currentRow.isEmpty { rows.append(currentRow) }
        return rows
    }

    static func measuredWidth(for title: String) -> CGFloat {
        let font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.systemFont(ofSize: 10, weight: .semibold)
        )
        let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
        return min(maximumWidth, ceil(textWidth) + horizontalPadding * 2)
    }
}

enum RoleSelection {
    static func toggled(_ roleID: UUID, in selectedRoleIDs: Set<UUID>) -> Set<UUID> {
        var result = selectedRoleIDs
        if result.contains(roleID) {
            result.remove(roleID)
        } else {
            result.insert(roleID)
        }
        return result
    }
}

private struct RoleSelectorWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 320

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TabOverviewInitialContext: Equatable {
    let isPrivate: Bool
    let identityID: UUID?
    let roleIDs: Set<UUID>

    static func resolve(
        selectedTab: BrowserTab?,
        fallbackIdentityID: UUID?
    ) -> TabOverviewInitialContext {
        guard let selectedTab else {
            return TabOverviewInitialContext(
                isPrivate: false,
                identityID: fallbackIdentityID,
                roleIDs: []
            )
        }

        return TabOverviewInitialContext(
            isPrivate: selectedTab.isPrivate,
            identityID: selectedTab.isPrivate ? nil : (selectedTab.identityID ?? fallbackIdentityID),
            roleIDs: Set(selectedTab.roleIDs ?? [])
        )
    }
}

enum TabOverviewInitialFocus {
    static func targetID(sourceTabID: UUID?, visibleTabs: [BrowserTab]) -> UUID? {
        guard let sourceTabID,
              visibleTabs.contains(where: { $0.id == sourceTabID }) else { return nil }
        return sourceTabID
    }
}

enum TabCardLayout {
    static let gridSpacing: CGFloat = 12
    static let closeOverlapInset: CGFloat = 6
    static let previewHeight: CGFloat = 84
    static let contentHeight: CGFloat = 184
    static let outerHeight: CGFloat = 196
    static let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: gridSpacing),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: gridSpacing)
    ]
}

enum PinnedTabDockPresentation {
    static let itemWidth: CGFloat = 72
    static let iconSpacing: CGFloat = 12
    static let height: CGFloat = 72

    static func tabs(
        from pinnedTabs: [BrowserTab],
        showsTabsSection: Bool,
        isPrivate: Bool
    ) -> [BrowserTab] {
        guard showsTabsSection, !isPrivate else { return [] }
        return pinnedTabs.filter { !$0.isPrivate }
    }
}

enum TabOverviewSection: String, CaseIterable, Identifiable {
    case tabs
    case bookmarks
    case downloads
    case readingList
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .tabs: "Tabs"
        case .bookmarks: "Saved"
        case .history: "History"
        case .readingList: "Library"
        case .downloads: "Downloads"
        }
    }

    func navigationTitle(isIncognito: Bool) -> String {
        let baseTitle = self == .bookmarks ? "Saved Bookmarks" : title
        return isIncognito ? "Incognito \(baseTitle)" : baseTitle
    }

    var systemImage: String {
        switch self {
        case .tabs: "square.on.square"
        case .bookmarks: "bookmark"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .readingList: "books.vertical"
        }
    }
}
