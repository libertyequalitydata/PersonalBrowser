import Foundation
import UniformTypeIdentifiers

enum BrowserDownloadInterruption {
    static func matches(_ error: Error) -> Bool {
        let error = error as NSError
        if error.code == 102 || matches(error.localizedDescription) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return matches(underlying)
        }
        return false
    }

    static func matches(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("frame load interrupted")
    }
}

enum BrowserDownloadSupport {
    private static let legacyVerificationFixtureCutoff = Date(timeIntervalSince1970: 1_791_320_400)

    static func downloadsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    static func libraryDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalBrowser", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }

    static func libraryKind(for record: BrowserDownloadRecord) -> LibraryArtifactKind {
        if mediaKind(for: record) == .audio { return .audio }
        if mediaKind(for: record) == .video { return .video }
        if isPDF(record) { return .pdf }
        return .document
    }

    static func resumeDataDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalBrowser", isDirectory: true)
            .appendingPathComponent("DownloadResumeData", isDirectory: true)
    }

    static func saveResumeData(
        _ data: Data,
        downloadID: UUID,
        directory: URL = resumeDataDirectory(),
        fileManager: FileManager = .default
    ) throws -> String {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "\(downloadID.uuidString).resume"
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    static func loadResumeData(
        filename: String?,
        directory: URL = resumeDataDirectory()
    ) -> Data? {
        guard let filename else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(filename))
    }

    static func removeResumeData(
        filename: String?,
        directory: URL = resumeDataDirectory(),
        fileManager: FileManager = .default
    ) {
        guard let filename else { return }
        try? fileManager.removeItem(at: directory.appendingPathComponent(filename))
    }

    static func contentType(
        mimeType: String?,
        filename: String
    ) -> UTType? {
        let pathExtension = (filename as NSString).pathExtension
        let extensionType = pathExtension.isEmpty ? nil : UTType(filenameExtension: pathExtension)
        guard let mimeType else { return extensionType }

        let normalizedMIME = mimeType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let genericMIMETypes: Set<String> = [
            "application/octet-stream",
            "binary/octet-stream",
            "application/download",
            "application/force-download"
        ]
        if let normalizedMIME, genericMIMETypes.contains(normalizedMIME) {
            return extensionType ?? UTType(mimeType: normalizedMIME)
        }
        return normalizedMIME.flatMap { UTType(mimeType: $0) } ?? extensionType
    }

    static func typeDescription(for record: BrowserDownloadRecord) -> String {
        if mediaKind(for: record) == .video { return "Video" }
        if mediaKind(for: record) == .audio { return "Audio" }
        let type = record.typeIdentifier.flatMap(UTType.init)
            ?? contentType(mimeType: record.mimeType, filename: record.fileName)
        guard let type else { return "File" }
        if type.conforms(to: .pdf) { return "PDF document" }
        if type.conforms(to: .image) { return "Image" }
        if type.conforms(to: .movie) { return "Video" }
        if type.conforms(to: .audio) { return "Audio" }
        if type.conforms(to: .archive) { return "Archive" }
        if type.conforms(to: .spreadsheet) { return "Spreadsheet" }
        if type.conforms(to: .presentation) { return "Presentation" }
        if type.conforms(to: .text) { return "Text document" }
        if type.conforms(to: .content) { return "Document" }
        return type.localizedDescription ?? "File"
    }

    static func systemImage(for record: BrowserDownloadRecord) -> String {
        if mediaKind(for: record) == .video { return "film" }
        if mediaKind(for: record) == .audio { return "waveform" }
        let type = record.typeIdentifier.flatMap(UTType.init)
            ?? contentType(mimeType: record.mimeType, filename: record.fileName)
        guard let type else { return "doc" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .archive) { return "archivebox" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    static func isPDF(_ record: BrowserDownloadRecord) -> Bool {
        let type = record.typeIdentifier.flatMap(UTType.init)
            ?? contentType(mimeType: record.mimeType, filename: record.fileName)
        return type?.conforms(to: .pdf) == true
    }

    static func mediaKind(for record: BrowserDownloadRecord) -> BrowserMediaKind? {
        let normalizedMIME = record.mimeType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedMIME?.hasPrefix("video/") == true { return .video }
        if normalizedMIME?.hasPrefix("audio/") == true { return .audio }

        let types = mediaTypeCandidates(for: record)
        if types.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
            return .video
        }
        if types.contains(where: { $0.conforms(to: .audio) }) { return .audio }

        let extensions = [
            (record.fileName as NSString).pathExtension,
            (record.localFilename as NSString).pathExtension,
            record.sourceURL.pathExtension
        ].map { $0.lowercased() }
        let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "avi", "mpeg", "mpg", "3gp", "3g2"]
        let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "ogg", "oga", "opus"]
        if extensions.contains(where: videoExtensions.contains) { return .video }
        if extensions.contains(where: audioExtensions.contains) { return .audio }
        return nil
    }

    private static func mediaTypeCandidates(for record: BrowserDownloadRecord) -> [UTType] {
        var types: [UTType] = []
        if let type = record.typeIdentifier.flatMap(UTType.init) { types.append(type) }
        if let mimeType = record.mimeType,
           let normalizedMIME = mimeType.split(separator: ";", maxSplits: 1).first,
           let type = UTType(mimeType: String(normalizedMIME).trimmingCharacters(in: .whitespacesAndNewlines)) {
            types.append(type)
        }
        for pathExtension in [
            (record.fileName as NSString).pathExtension,
            (record.localFilename as NSString).pathExtension,
            record.sourceURL.pathExtension
        ] where !pathExtension.isEmpty {
            if let type = UTType(filenameExtension: pathExtension) { types.append(type) }
        }
        return types
    }

    static func byteCountDescription(_ count: Int64?) -> String? {
        guard let count, count >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func isLegacyVerificationFixture(_ record: BrowserDownloadRecord) -> Bool {
        guard record.createdAt < legacyVerificationFixtureCutoff,
              record.sourceURL.host?.lowercased() == "httpbin.org",
              record.sourceURL.path == "/bytes/32" else { return false }

        let fixtureName = try? NSRegularExpression(pattern: #"^32(?: \([0-9]+\))?$"#)
        let range = NSRange(record.fileName.startIndex..<record.fileName.endIndex, in: record.fileName)
        guard fixtureName?.firstMatch(in: record.fileName, range: range) != nil else { return false }

        let recordedSize = record.fileByteCount ?? record.expectedByteCount
        return recordedSize == nil || recordedSize == 32
    }

    static func safeFilename(suggested: String, sourceURL: URL?) -> String {
        let fallback = nonBlank(sourceURL?.lastPathComponent) ?? "Download"
        let candidate = nonBlank(suggested) ?? fallback
        let invalid = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let sanitized = candidate
            .components(separatedBy: invalid)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((nonBlank(sanitized) ?? "Download").prefix(180))
    }

    static func uniqueDestinationURL(
        suggestedFilename: String,
        sourceURL: URL?,
        directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = safeFilename(suggested: suggestedFilename, sourceURL: sourceURL)
        let extensionName = (safeName as NSString).pathExtension
        let stem = nonBlank((safeName as NSString).deletingPathExtension) ?? "Download"
        var candidate = directory.appendingPathComponent(safeName, isDirectory: false)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let numberedName = extensionName.isEmpty
                ? "\(stem) (\(suffix))"
                : "\(stem) (\(suffix)).\(extensionName)"
            candidate = directory.appendingPathComponent(numberedName, isDirectory: false)
            suffix += 1
        }
        return candidate
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct BrowserDownloadDaySection: Identifiable, Equatable {
    let day: Date
    let title: String
    let downloads: [BrowserDownloadRecord]

    var id: Date { day }
}

enum BrowserDownloadGrouping {
    static func sections(
        for downloads: [BrowserDownloadRecord],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [BrowserDownloadDaySection] {
        let grouped = Dictionary(grouping: downloads) {
            calendar.startOfDay(for: $0.completedAt ?? $0.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            return BrowserDownloadDaySection(
                day: day,
                title: BrowserDaySectionTitle.title(for: day, now: now, calendar: calendar),
                downloads: grouped[day, default: []].sorted {
                    ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt)
                }
            )
        }
    }
}
