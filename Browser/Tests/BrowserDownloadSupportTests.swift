import XCTest
import Network
import WebKit
@testable import PersonalBrowser

final class BrowserDownloadSupportTests: XCTestCase {
    func testDownloadedVideoUsesBrowserOwnedMinimizableSurface() {
        XCTAssertTrue(BrowserDownloadedMediaPresentation.usesBrowserOwnedMediaSurface)
        XCTAssertTrue(BrowserDownloadedMediaPresentation.nativePlayerControllerIsExcluded)
        XCTAssertFalse(BrowserDownloadedMediaPresentation.minimizeStopsPlayback)
    }

    @MainActor
    func testPlaybackRateCanBeChangedWithoutCreatingAnAudioSessionError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("recording.m4a")
        try Data().write(to: fileURL)
        let playback = BrowserMediaPlaybackController()

        playback.play(url: fileURL, title: "Recording", kind: .audio)
        playback.setPlaybackRate(1.5)

        XCTAssertEqual(playback.playbackRate, 1.5)
        XCTAssertNil(playback.playbackError)
        playback.stop()
    }

    @MainActor
    func testVideoCanMinimizeWithoutStoppingAndRestoreItsPlayerSurface() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("clip.mp4")
        try Data().write(to: fileURL)
        let playback = BrowserMediaPlaybackController()

        playback.play(url: fileURL, title: "Clip", kind: .video)
        XCTAssertEqual(playback.currentItem?.url, fileURL)
        XCTAssertNotNil(playback.presentedItem)

        playback.minimizePlayerSurface()
        XCTAssertEqual(playback.currentItem?.url, fileURL)
        XCTAssertNil(playback.presentedItem)

        playback.restorePlayerSurface()
        XCTAssertNotNil(playback.presentedItem)

        playback.dismissPlayerSurface()
        XCTAssertNil(playback.currentItem)
        XCTAssertNil(playback.presentedItem)
    }

    @MainActor
    func testAudioUsesSameBrowserOwnedMinimizePathAndForcesAudiblePlayerState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("recording.m4a")
        try Data().write(to: fileURL)
        let playback = BrowserMediaPlaybackController()

        playback.play(url: fileURL, title: "Recording", kind: .audio)

        XCTAssertEqual(playback.currentItem?.kind, .audio)
        XCTAssertEqual(playback.presentedItem?.kind, .audio)
        XCTAssertFalse(playback.player.isMuted)
        XCTAssertEqual(playback.player.volume, 1)

        playback.minimizePlayerSurface()
        XCTAssertNotNil(playback.currentItem)
        XCTAssertNil(playback.presentedItem)

        playback.restorePlayerSurface()
        XCTAssertEqual(playback.presentedItem?.kind, .audio)
        playback.stop()
    }

    func testMediaKindSeparatesDownloadedAudioAndVideoFromDocuments() {
        let audio = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/audio.mp3")!,
            fileName: "audio.mp3",
            localFilename: "audio.mp3",
            identityID: UUID(),
            isIncognito: false,
            mimeType: "audio/mpeg"
        )
        let video = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/video.mp4")!,
            fileName: "video.mp4",
            localFilename: "video.mp4",
            identityID: UUID(),
            isIncognito: false,
            mimeType: "video/mp4"
        )
        let document = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/report.pdf")!,
            fileName: "report.pdf",
            localFilename: "report.pdf",
            identityID: UUID(),
            isIncognito: false,
            mimeType: "application/pdf"
        )

        XCTAssertEqual(BrowserDownloadSupport.mediaKind(for: audio), .audio)
        XCTAssertEqual(BrowserDownloadSupport.mediaKind(for: video), .video)
        XCTAssertNil(BrowserDownloadSupport.mediaKind(for: document))
    }

    func testGenericDownloadMIMEFallsBackToMediaFilenameAndSourceExtension() {
        let video = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/download")!,
            fileName: "presentation.mp4",
            localFilename: "presentation.mp4",
            identityID: UUID(),
            isIncognito: false,
            mimeType: "application/octet-stream",
            typeIdentifier: "public.data"
        )
        let audio = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/audio/session.m4a")!,
            fileName: "session",
            localFilename: "session",
            identityID: UUID(),
            isIncognito: false,
            mimeType: "application/force-download",
            typeIdentifier: "public.data"
        )

        XCTAssertEqual(BrowserDownloadSupport.mediaKind(for: video), .video)
        XCTAssertEqual(BrowserDownloadSupport.mediaKind(for: audio), .audio)
        XCTAssertEqual(BrowserDownloadSupport.typeDescription(for: video), "Video")
        XCTAssertEqual(BrowserDownloadSupport.typeDescription(for: audio), "Audio")
        XCTAssertEqual(BrowserDownloadSupport.systemImage(for: video), "film")
        XCTAssertEqual(BrowserDownloadSupport.systemImage(for: audio), "waveform")
    }

    func testRecognizesOnlyLegacyThirtyTwoByteHTTPBinFixtures() throws {
        let fixture = BrowserDownloadRecord(
            sourceURL: try XCTUnwrap(URL(string: "https://httpbin.org/bytes/32")),
            fileName: "32 (4)",
            localFilename: "32 (4)",
            identityID: UUID(),
            isIncognito: false,
            createdAt: Date(timeIntervalSince1970: 1_791_000_000),
            state: .completed,
            progress: 1,
            fileByteCount: 32
        )
        var ordinaryDownload = fixture
        ordinaryDownload.fileByteCount = 64

        XCTAssertTrue(BrowserDownloadSupport.isLegacyVerificationFixture(fixture))
        XCTAssertFalse(BrowserDownloadSupport.isLegacyVerificationFixture(ordinaryDownload))
    }

    func testFilenameIsSanitized() {
        XCTAssertEqual(
            BrowserDownloadSupport.safeFilename(
                suggested: "quarter/plan:final.pdf",
                sourceURL: URL(string: "https://example.com/fallback.pdf")
            ),
            "quarter-plan-final.pdf"
        )
    }

    func testBlankFilenameFallsBackToSourcePath() {
        XCTAssertEqual(
            BrowserDownloadSupport.safeFilename(
                suggested: "   ",
                sourceURL: URL(string: "https://example.com/report.pdf")
            ),
            "report.pdf"
        )
    }

    func testDestinationAvoidsExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("report.pdf")
        try Data().write(to: existing)

        let destination = try BrowserDownloadSupport.uniqueDestinationURL(
            suggestedFilename: "report.pdf",
            sourceURL: nil,
            directory: directory
        )

        XCTAssertEqual(destination.lastPathComponent, "report (2).pdf")
    }

    func testPDFHasDistinctTypeAndVisualClassification() {
        let pdf = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/report.pdf")!,
            fileName: "Annual report.pdf",
            localFilename: "Annual report.pdf",
            identityID: nil,
            isIncognito: false
        )
        let document = BrowserDownloadRecord(
            sourceURL: URL(string: "https://example.com/notes.txt")!,
            fileName: "Notes.txt",
            localFilename: "Notes.txt",
            identityID: nil,
            isIncognito: false
        )

        XCTAssertTrue(BrowserDownloadSupport.isPDF(pdf))
        XCTAssertFalse(BrowserDownloadSupport.isPDF(document))
        XCTAssertEqual(BrowserDownloadSupport.typeDescription(for: pdf), "PDF document")
        XCTAssertNotEqual(
            BrowserDownloadSupport.systemImage(for: pdf),
            BrowserDownloadSupport.systemImage(for: document)
        )
        XCTAssertEqual(BrowserDownloadSupport.libraryKind(for: pdf), .pdf)
        XCTAssertEqual(BrowserDownloadSupport.libraryKind(for: document), .document)
    }

    func testDownloadSourceVisualMetadataSurvivesCoding() throws {
        let record = BrowserDownloadRecord(
            sourceURL: URL(string: "https://cdn.example.com/file.pdf")!,
            fileName: "file.pdf",
            localFilename: "file.pdf",
            identityID: nil,
            isIncognito: false,
            sourcePageURL: URL(string: "https://example.com/article"),
            sourceFaviconURL: URL(string: "https://example.com/favicon.ico")
        )

        let decoded = try JSONDecoder().decode(
            BrowserDownloadRecord.self,
            from: JSONEncoder().encode(record)
        )

        XCTAssertEqual(decoded.sourcePageURL, record.sourcePageURL)
        XCTAssertEqual(decoded.sourceFaviconURL, record.sourceFaviconURL)
    }

    func testEveryFrameInterruptionFormIsRecognized() {
        XCTAssertTrue(
            BrowserDownloadInterruption.matches(
                NSError(domain: WKError.errorDomain, code: 102)
            )
        )
        XCTAssertTrue(
            BrowserDownloadInterruption.matches(
                NSError(domain: "UnexpectedWebKitWrapper", code: 102)
            )
        )
        XCTAssertTrue(BrowserDownloadInterruption.matches("Frame load interrupted"))
        XCTAssertTrue(
            BrowserDownloadInterruption.matches(
                NSError(
                    domain: NSURLErrorDomain,
                    code: -1,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: WKError.errorDomain, code: 102)]
                )
            )
        )
    }

    @MainActor
    func testWebPageDownloadsAttachmentEndToEnd() async throws {
        let server = try LocalDownloadServer()
        defer { server.stop() }
        try await server.start()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let page = WebPage(tab: BrowserTab(identityID: UUID()), downloadDirectory: directory)
        let finished = expectation(description: "WKDownload finishes")
        var record: BrowserDownloadRecord?

        page.onNavigationCommitted = { _, _, _ in
            Task { @MainActor in
                _ = try? await page.webView.evaluateJavaScript(
                    "document.getElementById('download').click()"
                )
            }
        }
        page.onDownloadStarted = { record = $0 }
        var completedByteCount: Int64?
        page.onDownloadFinished = { _, byteCount, _ in
            completedByteCount = byteCount
            finished.fulfill()
        }
        page.onDownloadFailed = { _, message, _, _ in
            XCTFail("Download failed: \(message)")
            finished.fulfill()
        }

        page.load(server.pageURL)
        await fulfillment(of: [finished], timeout: 8)
        XCTAssertNil(page.errorMessage, "Web view error: \(page.errorMessage ?? "unknown")")

        let completedRecord = try XCTUnwrap(record)
        XCTAssertEqual(completedRecord.fileName, "browser-readiness-proof.txt")
        XCTAssertEqual(completedRecord.mimeType, "text/plain")
        XCTAssertEqual(completedRecord.expectedByteCount, 35)
        XCTAssertEqual(completedByteCount, 35)
        XCTAssertEqual(BrowserDownloadSupport.typeDescription(for: completedRecord), "Text document")
        let downloadedURL = directory.appendingPathComponent(completedRecord.localFilename)
        XCTAssertEqual(
            try Data(contentsOf: downloadedURL),
            Data("Browser download integration proof\n".utf8)
        )
        XCTAssertEqual(page.downloadNotice?.message, "Downloaded browser-readiness-proof.txt")
    }

    @MainActor
    func testResponseAttachmentDownloadDoesNotSurfaceFrameInterruption() async throws {
        let server = try LocalDownloadServer()
        defer { server.stop() }
        try await server.start()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let page = WebPage(tab: BrowserTab(identityID: UUID()), downloadDirectory: directory)
        let finished = expectation(description: "Response attachment finishes")

        page.onNavigationCommitted = { _, _, _ in
            Task { @MainActor in
                _ = try? await page.webView.evaluateJavaScript(
                    "document.getElementById('response-download').click()"
                )
            }
        }
        page.onDownloadFinished = { _, _, _ in finished.fulfill() }
        page.onDownloadFailed = { _, message, _, _ in
            XCTFail("Download failed: \(message)")
            finished.fulfill()
        }

        page.load(server.pageURL)
        await fulfillment(of: [finished], timeout: 8)

        XCTAssertNil(page.errorMessage)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("browser-readiness-proof.txt").path
            )
        )
    }

    func testResumeDataCanBePersistedLoadedAndRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("resume-token".utf8)

        let filename = try BrowserDownloadSupport.saveResumeData(
            payload,
            downloadID: UUID(),
            directory: directory
        )

        XCTAssertEqual(
            BrowserDownloadSupport.loadResumeData(filename: filename, directory: directory),
            payload
        )
        BrowserDownloadSupport.removeResumeData(filename: filename, directory: directory)
        XCTAssertNil(BrowserDownloadSupport.loadResumeData(filename: filename, directory: directory))
    }

    func testDownloadsAreGroupedByDisplayDayAndSortedNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 10,
            day: 4,
            hour: 12
        )))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let older = try XCTUnwrap(calendar.date(byAdding: .day, value: -4, to: now))
        let records = [
            BrowserDownloadRecord(
                sourceURL: URL(string: "https://example.com/older.pdf")!,
                fileName: "older.pdf",
                localFilename: "older.pdf",
                identityID: nil,
                isIncognito: false,
                createdAt: older
            ),
            BrowserDownloadRecord(
                sourceURL: URL(string: "https://example.com/yesterday.pdf")!,
                fileName: "yesterday.pdf",
                localFilename: "yesterday.pdf",
                identityID: nil,
                isIncognito: false,
                createdAt: yesterday
            ),
            BrowserDownloadRecord(
                sourceURL: URL(string: "https://example.com/today.pdf")!,
                fileName: "today.pdf",
                localFilename: "today.pdf",
                identityID: nil,
                isIncognito: false,
                createdAt: now
            )
        ]

        let sections = BrowserDownloadGrouping.sections(
            for: records,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.title).prefix(2), ["Today", "Yesterday"])
        XCTAssertEqual(sections.flatMap(\.downloads).map(\.fileName), [
            "today.pdf",
            "yesterday.pdf",
            "older.pdf"
        ])
    }

    @MainActor
    func testFailedDownloadCanRestartWithSameRecordID() async throws {
        let server = try LocalDownloadServer()
        defer { server.stop() }
        try await server.start()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let page = WebPage(tab: BrowserTab(identityID: UUID()), downloadDirectory: directory)
        let originalID = UUID()
        let record = BrowserDownloadRecord(
            id: originalID,
            sourceURL: server.downloadURL,
            fileName: "browser-readiness-proof.txt",
            localFilename: "browser-readiness-proof.txt",
            identityID: UUID(),
            isIncognito: false,
            state: .failed,
            errorDescription: "Interrupted"
        )
        let finished = expectation(description: "Retry finishes")
        var restartedRecord: BrowserDownloadRecord?
        page.onDownloadStarted = { restartedRecord = $0 }
        page.onDownloadFinished = { id, _, _ in
            XCTAssertEqual(id, originalID)
            finished.fulfill()
        }
        page.onDownloadFailed = { _, message, _, _ in
            XCTFail("Retry failed: \(message)")
            finished.fulfill()
        }

        XCTAssertTrue(page.retryDownload(record, resumeData: nil))
        await fulfillment(of: [finished], timeout: 8)
        XCTAssertEqual(restartedRecord?.id, originalID)
        XCTAssertEqual(restartedRecord?.createdAt, record.createdAt)
    }
}

private final class LocalDownloadServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "BrowserDownloadSupportTests.LocalDownloadServer")
    private var readyContinuation: CheckedContinuation<Void, Error>?

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
    }

    var pageURL: URL {
        URL(string: "http://localhost:\(listener.port!.rawValue)/")!
    }

    var downloadURL: URL {
        URL(string: "http://localhost:\(listener.port!.rawValue)/download")!
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.resumeReady()
                case .failed(let error):
                    self.resumeReady(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func resumeReady(throwing error: Error? = nil) {
        guard let continuation = readyContinuation else { return }
        readyContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let downloadsFile = request.hasPrefix("GET /download ")
                || request.hasPrefix("GET /response-download ")
            let body = downloadsFile
                ? Data("Browser download integration proof\n".utf8)
                : Data("""
                    <html><body>
                    <a id='download' href='/download' download>Download</a>
                    <a id='response-download' href='/response-download'>Response download</a>
                    </body></html>
                    """.utf8)
            var headers = [
                "HTTP/1.1 200 OK",
                "Content-Type: \(downloadsFile ? "text/plain; charset=utf-8" : "text/html; charset=utf-8")"
            ]
            if downloadsFile {
                headers.append("Content-Disposition: attachment; filename=browser-readiness-proof.txt")
            }
            headers.append(contentsOf: [
                "Content-Length: \(body.count)",
                "Connection: close",
                "",
                ""
            ])
            let headerData = headers.joined(separator: "\r\n")
            var response = Data(headerData.utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
