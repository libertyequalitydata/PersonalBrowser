import Foundation

enum ReadingListMutation: Equatable {
    case inserted
    case updated

    var feedbackMessage: String {
        switch self {
        case .inserted: "Added to Library"
        case .updated: "Library item updated"
        }
    }
}

struct BrowserIdentity: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, colorHex: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

struct BrowserRole: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var key: String
    var name: String
    var colorHex: String
    var preferredIdentityID: UUID?
    var isArchived: Bool
    var usageCount: Int?
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        key: String,
        name: String,
        colorHex: String,
        preferredIdentityID: UUID? = nil,
        isArchived: Bool = false,
        usageCount: Int? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.key = key
        self.name = name
        self.colorHex = colorHex
        self.preferredIdentityID = preferredIdentityID
        self.isArchived = isArchived
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
    }
}

struct BrowserTab: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var identityID: UUID?
    var url: URL?
    var title: String
    var siteName: String?
    var faviconURL: URL?
    var previewImageURL: URL?
    var snapshotFilename: String?
    var roleIDs: [UUID]?
    var isPrivate: Bool
    var pinnedAt: Date?
    var browserControlsHidden: Bool?
    var linkOpeningPolicy: BrowserLinkOpeningPolicy?
    let createdAt: Date
    var lastActiveAt: Date

    init(
        id: UUID = UUID(),
        identityID: UUID?,
        url: URL? = nil,
        title: String = "New Tab",
        siteName: String? = nil,
        faviconURL: URL? = nil,
        previewImageURL: URL? = nil,
        snapshotFilename: String? = nil,
        roleIDs: [UUID] = [],
        isPrivate: Bool = false,
        pinnedAt: Date? = nil,
        browserControlsHidden: Bool? = nil,
        linkOpeningPolicy: BrowserLinkOpeningPolicy? = nil,
        createdAt: Date = .now,
        lastActiveAt: Date = .now
    ) {
        self.id = id
        self.identityID = identityID
        self.url = url
        self.title = title
        self.siteName = siteName
        self.faviconURL = faviconURL
        self.previewImageURL = previewImageURL
        self.snapshotFilename = snapshotFilename
        self.roleIDs = roleIDs
        self.isPrivate = isPrivate
        self.pinnedAt = isPrivate ? nil : pinnedAt
        self.browserControlsHidden = browserControlsHidden
        self.linkOpeningPolicy = linkOpeningPolicy
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }

    var isPinned: Bool { pinnedAt != nil }
    var keepsBrowserControlsHidden: Bool { browserControlsHidden == true }
    /// Retained only so builds predating site-scoped link preferences can decode
    /// and migrate their per-tab value. New state always leaves this nil.
    var effectiveLinkOpeningPolicy: BrowserLinkOpeningPolicy { linkOpeningPolicy ?? .followWebsite }
    var isUncommittedBlank: Bool { url == nil }
}

enum BrowserLinkOpeningPolicy: String, Codable, CaseIterable, Identifiable {
    case followWebsite
    case sameTab
    case newTab
    case subtab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followWebsite: "Follow Website"
        case .sameTab: "Same Tab"
        case .newTab: "New Tab"
        case .subtab: "Subtab"
        }
    }

    var compactTitle: String {
        switch self {
        case .followWebsite: "Website"
        case .sameTab: "Same Tab"
        case .newTab: "New Tab"
        case .subtab: "Subtab"
        }
    }

    var systemImage: String {
        switch self {
        case .followWebsite: "arrow.triangle.branch"
        case .sameTab: "rectangle"
        case .newTab: "plus.square.on.square"
        case .subtab: "macwindow.on.rectangle"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "previewPanel" {
            self = .subtab
        } else if let value = Self(rawValue: rawValue) {
            self = value
        } else {
            self = .followWebsite
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct BrowserSubtabRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL?
}

struct BrowserHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let visitedAt: Date
    let identityID: UUID
    let url: URL
    let title: String
    var siteName: String?
    var faviconURL: URL?
    var roleIDs: [UUID]?

    init(
        id: UUID = UUID(),
        visitedAt: Date = .now,
        identityID: UUID,
        url: URL,
        title: String,
        siteName: String? = nil,
        faviconURL: URL? = nil,
        roleIDs: [UUID] = []
    ) {
        self.id = id
        self.visitedAt = visitedAt
        self.identityID = identityID
        self.url = url
        self.title = title
        self.siteName = siteName
        self.faviconURL = faviconURL
        self.roleIDs = roleIDs
    }
}

struct BrowserAttentionRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date
    var url: URL
    var title: String
    var siteName: String?
    var faviconURL: URL?
    var roleIDs: [UUID]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        url: URL,
        title: String,
        siteName: String? = nil,
        faviconURL: URL? = nil,
        roleIDs: [UUID] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.url = url
        self.title = title
        self.siteName = siteName
        self.faviconURL = faviconURL
        self.roleIDs = roleIDs
    }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

struct BrowserMediaUsageRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date
    var sourceURL: URL
    var title: String
    var kind: BrowserMediaKind
    var activeSeconds: TimeInterval
    var roleIDs: [UUID]

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        sourceURL: URL,
        title: String,
        kind: BrowserMediaKind,
        activeSeconds: TimeInterval,
        roleIDs: [UUID] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceURL = sourceURL
        self.title = title
        self.kind = kind
        self.activeSeconds = max(0, activeSeconds)
        self.roleIDs = roleIDs
    }
}

struct Bookmark: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let createdAt: Date
    var url: URL
    var title: String
    var preferredIdentityID: UUID?
    var isIncognito: Bool
    var siteName: String?
    var faviconURL: URL?
    var roleIDs: [UUID]?
    var savedListIDs: [UUID]?
    var note: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        url: URL,
        title: String,
        preferredIdentityID: UUID?,
        isIncognito: Bool = false,
        siteName: String? = nil,
        faviconURL: URL? = nil,
        roleIDs: [UUID] = [],
        savedListIDs: [UUID] = [],
        note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.url = url
        self.title = title
        self.preferredIdentityID = preferredIdentityID
        self.isIncognito = isIncognito
        self.siteName = siteName
        self.faviconURL = faviconURL
        self.roleIDs = roleIDs
        self.savedListIDs = savedListIDs
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case url
        case title
        case preferredIdentityID
        case isIncognito
        case siteName
        case faviconURL
        case roleIDs
        case savedListIDs
        case note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        url = try container.decode(URL.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        preferredIdentityID = try container.decodeIfPresent(UUID.self, forKey: .preferredIdentityID)
        isIncognito = try container.decodeIfPresent(Bool.self, forKey: .isIncognito) ?? false
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        faviconURL = try container.decodeIfPresent(URL.self, forKey: .faviconURL)
        roleIDs = try container.decodeIfPresent([UUID].self, forKey: .roleIDs)
        savedListIDs = try container.decodeIfPresent([UUID].self, forKey: .savedListIDs)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

struct SavedBookmarkList: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let createdAt: Date
    var name: String
    var isIncognito: Bool
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        name: String,
        isIncognito: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.isIncognito = isIncognito
        self.archivedAt = archivedAt
    }

    var isArchived: Bool { archivedAt != nil }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case name
        case isIncognito
        case archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        name = try container.decode(String.self, forKey: .name)
        isIncognito = try container.decodeIfPresent(Bool.self, forKey: .isIncognito) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}

struct BrowserBookmarkDaySection: Identifiable, Equatable {
    let day: Date
    let title: String
    let bookmarks: [Bookmark]

    var id: Date { day }
}

struct BrowserHistoryDaySection: Identifiable, Equatable {
    let day: Date
    let title: String
    let entries: [BrowserHistoryEntry]

    var id: Date { day }
}

enum BrowserDaySectionTitle {
    static func title(
        for day: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

enum BrowserLibraryGrouping {
    static func bookmarkSections(
        for bookmarks: [Bookmark],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [BrowserBookmarkDaySection] {
        let grouped = Dictionary(grouping: bookmarks) {
            calendar.startOfDay(for: $0.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            BrowserBookmarkDaySection(
                day: day,
                title: BrowserDaySectionTitle.title(for: day, now: now, calendar: calendar),
                bookmarks: grouped[day, default: []].sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    static func historySections(
        for entries: [BrowserHistoryEntry],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [BrowserHistoryDaySection] {
        let grouped = Dictionary(grouping: entries) {
            calendar.startOfDay(for: $0.visitedAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            BrowserHistoryDaySection(
                day: day,
                title: BrowserDaySectionTitle.title(for: day, now: now, calendar: calendar),
                entries: grouped[day, default: []].sorted { $0.visitedAt > $1.visitedAt }
            )
        }
    }
}

enum BrowserDownloadState: String, Codable, Equatable {
    case downloading
    case completed
    case failed
    case cancelled
}

struct BrowserDownloadNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let systemImage: String
    let isFailure: Bool
}

struct BrowserDownloadRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let sourceURL: URL
    let fileName: String
    let localFilename: String
    let identityID: UUID?
    let isIncognito: Bool
    let createdAt: Date
    var state: BrowserDownloadState
    var progress: Double
    var errorDescription: String?
    var mimeType: String?
    var typeIdentifier: String?
    var expectedByteCount: Int64?
    var fileByteCount: Int64?
    var completedAt: Date?
    var resumeDataFilename: String?
    var sourcePageURL: URL?
    var sourceFaviconURL: URL?
    var roleIDs: [UUID]?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        fileName: String,
        localFilename: String,
        identityID: UUID?,
        isIncognito: Bool,
        createdAt: Date = .now,
        state: BrowserDownloadState = .downloading,
        progress: Double = 0,
        errorDescription: String? = nil,
        mimeType: String? = nil,
        typeIdentifier: String? = nil,
        expectedByteCount: Int64? = nil,
        fileByteCount: Int64? = nil,
        completedAt: Date? = nil,
        resumeDataFilename: String? = nil,
        sourcePageURL: URL? = nil,
        sourceFaviconURL: URL? = nil,
        roleIDs: [UUID]? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.localFilename = localFilename
        self.identityID = identityID
        self.isIncognito = isIncognito
        self.createdAt = createdAt
        self.state = state
        self.progress = progress
        self.errorDescription = errorDescription
        self.mimeType = mimeType
        self.typeIdentifier = typeIdentifier
        self.expectedByteCount = expectedByteCount
        self.fileByteCount = fileByteCount
        self.completedAt = completedAt
        self.resumeDataFilename = resumeDataFilename
        self.sourcePageURL = sourcePageURL
        self.sourceFaviconURL = sourceFaviconURL
        self.roleIDs = roleIDs
    }
}

enum BrowserRoleFilter {
    static func includes(recordRoleIDs: [UUID]?, selectedRoleIDs: Set<UUID>) -> Bool {
        selectedRoleIDs.isEmpty
            || !selectedRoleIDs.isDisjoint(with: Set(recordRoleIDs ?? []))
    }
}

enum ReadingState: String, Codable, CaseIterable {
    case queued
    case reading
    case consumed
}

enum RetentionState: String, Codable, CaseIterable {
    case localOnly = "local_only"
    case saveRequested = "save_requested"
    case awaitingCore = "awaiting_core"
    case locallyAcknowledged = "locally_acknowledged"
    case piosAccepted = "pios_accepted"
    case retryable
    case rejected
}

enum CaptureKind: String, Codable {
    case referenceOnly = "reference_only"
    case readableCapture = "readable_capture"
}

struct ReaderDocument: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let sourceURL: URL
    let title: String
    let author: String?
    let siteName: String?
    let text: String
    let previewImageURL: URL?
    let capturedAt: Date
    let capturedIdentityID: UUID?
    let captureKind: CaptureKind

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        title: String,
        author: String? = nil,
        siteName: String? = nil,
        text: String,
        previewImageURL: URL? = nil,
        capturedAt: Date = .now,
        capturedIdentityID: UUID?,
        captureKind: CaptureKind
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.author = author
        self.siteName = siteName
        self.text = text
        self.previewImageURL = previewImageURL
        self.capturedAt = capturedAt
        self.capturedIdentityID = capturedIdentityID
        self.captureKind = captureKind
    }

    var contentSnippet: String {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

struct ReadingItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var document: ReaderDocument
    var readingState: ReadingState
    var retentionState: RetentionState
    var progress: Double?

    init(
        id: UUID = UUID(),
        document: ReaderDocument,
        readingState: ReadingState = .queued,
        retentionState: RetentionState = .localOnly,
        progress: Double? = nil
    ) {
        self.id = id
        self.document = document
        self.readingState = readingState
        self.retentionState = retentionState
        self.progress = progress
    }
}

enum LibraryArtifactKind: String, Codable, CaseIterable {
    case audio
    case video
    case pdf
    case document

    var title: String {
        switch self {
        case .audio: "Audio"
        case .video: "Video"
        case .pdf: "PDF"
        case .document: "Document"
        }
    }

    var systemImage: String {
        switch self {
        case .audio: "waveform"
        case .video: "film"
        case .pdf: "doc.richtext"
        case .document: "doc"
        }
    }
}

struct LibraryArtifact: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let sourceDownloadID: UUID?
    let sourceURL: URL
    let title: String
    let localFilename: String
    let kind: LibraryArtifactKind
    let mimeType: String?
    let typeIdentifier: String?
    let addedAt: Date
    let isIncognito: Bool
    var archivedAt: Date?
    var transcript: String?
    var transcriptLocaleIdentifier: String?

    init(
        id: UUID = UUID(),
        sourceDownloadID: UUID? = nil,
        sourceURL: URL,
        title: String,
        localFilename: String,
        kind: LibraryArtifactKind,
        mimeType: String? = nil,
        typeIdentifier: String? = nil,
        addedAt: Date = .now,
        isIncognito: Bool = false,
        archivedAt: Date? = nil,
        transcript: String? = nil,
        transcriptLocaleIdentifier: String? = nil
    ) {
        self.id = id
        self.sourceDownloadID = sourceDownloadID
        self.sourceURL = sourceURL
        self.title = title
        self.localFilename = localFilename
        self.kind = kind
        self.mimeType = mimeType
        self.typeIdentifier = typeIdentifier
        self.addedAt = addedAt
        self.isIncognito = isIncognito
        self.archivedAt = archivedAt
        self.transcript = transcript
        self.transcriptLocaleIdentifier = transcriptLocaleIdentifier
    }

    var isArchived: Bool { archivedAt != nil }
}

struct BrowserSnapshot: Codable, Equatable {
    var identities: [BrowserIdentity]
    var roles: [BrowserRole]?
    var tabs: [BrowserTab]
    var selectedTabID: UUID?
    var history: [BrowserHistoryEntry]
    var bookmarks: [Bookmark]
    var savedBookmarkLists: [SavedBookmarkList]? = nil
    var readingList: [ReadingItem]
    var downloads: [BrowserDownloadRecord]? = nil
    var libraryArtifacts: [LibraryArtifact]? = nil
    var attentionRecords: [BrowserAttentionRecord]? = nil
    var mediaUsageRecords: [BrowserMediaUsageRecord]? = nil
}
