import Charts
import SwiftUI

enum BrowsingInsightsPeriod: Int, CaseIterable, Identifiable {
    case today = 1
    case week = 7
    case month = 30

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }
}

struct BrowsingInsightSite: Identifiable, Equatable {
    let id: String
    let name: String
    let faviconURL: URL?
    let activeTime: TimeInterval
    let visits: Int
    let firstVisit: Date?
    let latestVisit: Date?
    let pages: [BrowserHistoryEntry]
}

struct BrowsingInsightDay: Identifiable, Equatable {
    let date: Date
    let seconds: TimeInterval
    var id: Date { date }
}

struct BrowsingInsightsSnapshot: Equatable {
    let activeTime: TimeInterval
    let days: [BrowsingInsightDay]
    let sites: [BrowsingInsightSite]
    let pagesVisited: Int
    let distinctSites: Int
    let savedCount: Int
    let libraryCount: Int
    let downloadCount: Int
    let mediaTime: TimeInterval
    let rhythm: [TimeInterval]

    init(
        attentionRecords: [BrowserAttentionRecord],
        history: [BrowserHistoryEntry],
        bookmarks: [Bookmark],
        libraryCount: Int,
        downloads: [BrowserDownloadRecord],
        mediaUsageRecords: [BrowserMediaUsageRecord],
        period: BrowsingInsightsPeriod,
        selectedRoleIDs: Set<UUID>,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let today = calendar.startOfDay(for: now)
        let start = period == .today
            ? today
            : calendar.date(byAdding: .day, value: -(period.rawValue - 1), to: today) ?? today
        let end = now
        let roleMatches: ([UUID]?) -> Bool = {
            BrowserRoleFilter.includes(recordRoleIDs: $0, selectedRoleIDs: selectedRoleIDs)
        }
        let relevantAttention = attentionRecords.filter {
            $0.endedAt > start && $0.startedAt <= end && roleMatches($0.roleIDs)
        }
        let relevantHistory = history.filter {
            $0.visitedAt >= start && $0.visitedAt <= end && roleMatches($0.roleIDs)
        }
        let relevantBookmarks = bookmarks.filter {
            !$0.isIncognito && $0.createdAt >= start && $0.createdAt <= end && roleMatches($0.roleIDs)
        }
        let relevantDownloads = downloads.filter {
            !$0.isIncognito && $0.createdAt >= start && $0.createdAt <= end && roleMatches($0.roleIDs)
        }
        let relevantMedia = mediaUsageRecords.filter {
            $0.endedAt > start && $0.startedAt <= end && roleMatches($0.roleIDs)
        }

        func clippedDuration(_ record: BrowserAttentionRecord) -> TimeInterval {
            max(0, min(record.endedAt, end).timeIntervalSince(max(record.startedAt, start)))
        }

        activeTime = relevantAttention.reduce(0) { $0 + clippedDuration($1) }
        pagesVisited = relevantHistory.count
        savedCount = relevantBookmarks.count
        downloadCount = relevantDownloads.count
        mediaTime = relevantMedia.reduce(0) { partial, record in
            let interval = max(0.001, record.endedAt.timeIntervalSince(record.startedAt))
            let overlap = max(0, min(record.endedAt, end).timeIntervalSince(max(record.startedAt, start)))
            return partial + record.activeSeconds * min(1, overlap / interval)
        }
        self.libraryCount = selectedRoleIDs.isEmpty ? libraryCount : 0

        let dayCount = period.rawValue
        days = (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let next = calendar.date(byAdding: .day, value: 1, to: date) ?? end
            let seconds = relevantAttention.reduce(0) { partial, record in
                partial + max(0, min(record.endedAt, next, end).timeIntervalSince(max(record.startedAt, date)))
            }
            return BrowsingInsightDay(date: date, seconds: seconds)
        }

        let historyBySite = Dictionary(grouping: relevantHistory) {
            SiteLinkOpeningPreferences.siteKey(for: $0.url) ?? $0.url.host ?? $0.url.absoluteString
        }
        let attentionBySite = Dictionary(grouping: relevantAttention) {
            SiteLinkOpeningPreferences.siteKey(for: $0.url) ?? $0.url.host ?? $0.url.absoluteString
        }
        let allSiteKeys = Set(historyBySite.keys).union(attentionBySite.keys)
        sites = allSiteKeys.map { key in
            let siteHistory = historyBySite[key, default: []].sorted { $0.visitedAt > $1.visitedAt }
            let siteAttention = attentionBySite[key, default: []]
            let seconds = siteAttention.reduce(0) { $0 + clippedDuration($1) }
            return BrowsingInsightSite(
                id: key,
                name: siteAttention.last?.siteName ?? siteHistory.first?.siteName ?? key,
                faviconURL: siteAttention.last?.faviconURL ?? siteHistory.first?.faviconURL,
                activeTime: seconds,
                visits: siteHistory.count,
                firstVisit: siteHistory.map(\.visitedAt).min(),
                latestVisit: siteHistory.map(\.visitedAt).max(),
                pages: siteHistory
            )
        }.sorted {
            if $0.activeTime == $1.activeTime { return $0.visits > $1.visits }
            return $0.activeTime > $1.activeTime
        }
        distinctSites = sites.count

        var rhythmBins = Array(repeating: TimeInterval.zero, count: 6)
        for record in relevantAttention {
            let hour = calendar.component(.hour, from: record.startedAt)
            rhythmBins[min(5, max(0, hour / 4))] += clippedDuration(record)
        }
        rhythm = rhythmBins
    }
}

struct BrowsingInsightsView: View {
    @EnvironmentObject private var store: BrowserStore
    let onBack: () -> Void

    @State private var period: BrowsingInsightsPeriod = .week
    @State private var selectedRoleIDs: Set<UUID> = []
    @State private var confirmingClear = false

    private var snapshot: BrowsingInsightsSnapshot {
        BrowsingInsightsSnapshot(
            attentionRecords: store.attentionRecords,
            history: store.history(incognitoOnly: false),
            bookmarks: store.bookmarks(incognitoOnly: false),
            libraryCount: store.readingList.count + store.libraryArtifacts.count,
            downloads: store.downloads,
            mediaUsageRecords: store.mediaUsageRecords,
            period: period,
            selectedRoleIDs: selectedRoleIDs
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    periodPicker
                    roleFilters
                    attentionCard
                    activitySummary
                    topSites
                    browsingRhythm
                    privacyCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .background(Color.browserCanvas)
            .navigationTitle("Browsing Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .preferredColorScheme(.light)
        .confirmationDialog(
            "Clear Measured Activity?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear Measured Activity", role: .destructive) {
                store.clearBrowsingInsights()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes locally measured browsing and media time. History, Saved items, Library items and Downloads remain unchanged.")
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(BrowsingInsightsPeriod.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    @ViewBuilder private var roleFilters: some View {
        if !store.activeRoles.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                ForEach(store.rolesByUsage(prioritizing: selectedRoleIDs)) { role in
                    Button {
                        selectedRoleIDs = RoleSelection.toggled(role.id, in: selectedRoleIDs)
                    } label: {
                        Label(role.name, image: "RolesIcon")
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .frame(minHeight: 32)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Color.browserInk)
                            .background(
                                selectedRoleIDs.contains(role.id)
                                    ? Color.browserInk.opacity(0.16)
                                    : Color.browserInk.opacity(0.06),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var attentionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACTIVE BROWSING")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(formatDuration(snapshot.activeTime))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(Color.browserInk)
            Chart(snapshot.days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Time", day.seconds))
                    .foregroundStyle(Color.browserAccent.gradient)
                    .cornerRadius(4)
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(snapshot.days.count, 7))) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 118)
        }
        .insightsCard()
    }

    private var activitySummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity")
                .font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("Pages visited", snapshot.pagesVisited, "doc.text")
                metric("Sites", snapshot.distinctSites, "globe")
                metric("Saved", snapshot.savedCount, "bookmark")
                metric("Library", snapshot.libraryCount, "books.vertical")
                metric("Downloads", snapshot.downloadCount, "arrow.down.circle")
                durationMetric("Media time", snapshot.mediaTime, "play.rectangle")
            }
        }
    }

    private var topSites: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top sites").font(.title3.weight(.bold))
            if snapshot.sites.isEmpty {
                Text("Your active browsing will appear here after you use normal tabs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .insightsCard()
            } else {
                ForEach(snapshot.sites.prefix(8)) { site in
                    NavigationLink {
                        BrowsingSiteInsightView(site: site, totalTime: snapshot.activeTime)
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: site.faviconURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "globe").foregroundStyle(Color.browserAccent)
                            }
                            .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(site.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("\(formatDuration(site.activeTime)) · \(site.visits) visits")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(snapshot.activeTime > 0 ? "\(Int((site.activeTime / snapshot.activeTime) * 100))%" : "—")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.forward").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(Color.browserInk)
                        .insightsCard()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var browsingRhythm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browsing rhythm").font(.title3.weight(.bold))
            Chart(Array(snapshot.rhythm.enumerated()), id: \.offset) { index, seconds in
                BarMark(x: .value("Period", index), y: .value("Time", seconds))
                    .foregroundStyle(Color.browserInk.opacity(0.72))
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: Array(0..<6)) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self) {
                            Text(["00", "04", "08", "12", "16", "20"][index])
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 112)
        }
        .insightsCard()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Your information", systemImage: "lock.shield")
                .font(.headline).foregroundStyle(Color.browserInk)
            Text("These insights are created and stored locally from normal browsing. Incognito is never included. Personal Browser does not send them to a service.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("In the future, you may choose to make selected information available to your Core and trusted personal agents.")
                .font(.subheadline.weight(.medium)).foregroundStyle(Color.browserInk)
            Button("Clear Measured Activity", role: .destructive) {
                confirmingClear = true
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(18)
        .background(Color.browserAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }

    private func metric(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.browserAccent)
            Text(value.formatted()).font(.title2.weight(.bold)).foregroundStyle(Color.browserInk)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCard()
    }

    private func durationMetric(_ title: String, _ value: TimeInterval, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.browserAccent)
            Text(formatDuration(value)).font(.title2.weight(.bold)).foregroundStyle(Color.browserInk)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .insightsCard()
    }
}

private struct BrowsingSiteInsightView: View {
    let site: BrowsingInsightSite
    let totalTime: TimeInterval

    var body: some View {
        List {
            Section {
                LabeledContent("Active time", value: formatDuration(site.activeTime))
                LabeledContent("Visits", value: site.visits.formatted())
                if let firstVisit = site.firstVisit { LabeledContent("First visit", value: firstVisit.formatted(date: .abbreviated, time: .shortened)) }
                if let latestVisit = site.latestVisit { LabeledContent("Latest visit", value: latestVisit.formatted(date: .abbreviated, time: .shortened)) }
                LabeledContent("Share of browsing", value: totalTime > 0 ? "\(Int(site.activeTime / totalTime * 100))%" : "—")
            }
            Section("Recent pages") {
                ForEach(site.pages.prefix(20)) { page in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(page.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text(page.visitedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.browserCanvas)
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func insightsCard() -> some View {
        padding(16)
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.browserInk.opacity(0.05)))
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration / 60)
    if minutes < 1 { return duration > 0 ? "< 1 min" : "0 min" }
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) hr \(minutes % 60) min"
}
