import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

struct ReaderSharePayload: Identifiable {
    let id = UUID()
    let itemURL: URL
    let cleanupURL: URL?

    static func originalLink(_ url: URL) -> ReaderSharePayload {
        ReaderSharePayload(itemURL: url, cleanupURL: nil)
    }

    static func exportedPDF(_ url: URL) -> ReaderSharePayload {
        ReaderSharePayload(itemURL: url, cleanupURL: url)
    }
}

struct ReaderShareActivityView: UIViewControllerRepresentable {
    let payload: ReaderSharePayload

    func makeCoordinator() -> Coordinator {
        Coordinator(cleanupURL: payload.cleanupURL)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [payload.itemURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.cleanup()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    static func dismantleUIViewController(
        _ controller: UIActivityViewController,
        coordinator: Coordinator
    ) {
        coordinator.cleanup()
    }

    final class Coordinator {
        private var cleanupURL: URL?

        init(cleanupURL: URL?) {
            self.cleanupURL = cleanupURL
        }

        func cleanup() {
            guard let cleanupURL else { return }
            try? FileManager.default.removeItem(at: cleanupURL)
            self.cleanupURL = nil
        }
    }
}

@MainActor
enum ReaderPDFExporter {
    static func export(_ document: ReaderDocument) async throws -> URL {
        let imageData = await ReaderRemoteImageLoader.load(
            from: document.previewImageURL,
            referringPageURL: document.sourceURL
        )
        let formatter = UIMarkupTextPrintFormatter(
            markupText: markup(for: document, imageData: imageData)
        )
        formatter.perPageContentInsets = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)

        let renderer = ReaderPDFPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, renderer.paperRect, [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextAuthor as String: document.author ?? document.siteName ?? "Personal Browser"
        ])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for pageIndex in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            let pageBounds = UIGraphicsGetPDFContextBounds()
            UIColor.white.setFill()
            UIRectFill(pageBounds)
            renderer.drawPage(at: pageIndex, in: pageBounds)
        }
        UIGraphicsEndPDFContext()

        guard data.length > 0 else { throw ReaderPDFExportError.renderFailed }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserReaderExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(
            "\(safeFilename(document.title))-\(UUID().uuidString.prefix(8)).pdf",
            isDirectory: false
        )
        try (data as Data).write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func markup(for document: ReaderDocument, imageData: Data?) -> String {
        let title = escape(document.title)
        let sourceName = escape(document.siteName ?? document.sourceURL.host ?? "Source")
        let author = document.author.map(escape)
        let byline = author.map { "<span class=\"separator\">•</span> \($0)" } ?? ""
        let image = imageData.map {
            "<img class=\"hero\" src=\"data:image/jpeg;base64,\($0.base64EncodedString())\" />"
        } ?? ""
        let reference = document.captureKind == .referenceOnly
            ? "<p class=\"reference\">Reference-only capture</p>"
            : ""
        let paragraphs = document.text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\(escape($0))</p>" }
            .joined(separator: "\n")
        let sourceURL = escape(document.sourceURL.absoluteString)

        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>
        @page { margin: 0; }
        * { box-sizing: border-box; }
        html, body, article { background: #ffffff; }
        body { margin: 0; color: #0a1f26; font-family: Georgia, 'Times New Roman', serif; font-size: 15pt; line-height: 1.58; }
        article { padding: 0; }
        h1 { margin: 0 0 10pt; font-size: 27pt; line-height: 1.12; font-weight: 700; }
        .meta { margin: 0 0 14pt; color: #687277; font: 10.5pt -apple-system, BlinkMacSystemFont, sans-serif; }
        .separator { padding: 0 5pt; }
        .reference { color: #d06d12; font: 600 10pt -apple-system, BlinkMacSystemFont, sans-serif; }
        .hero { display: block; width: 100%; max-height: 290pt; object-fit: contain; margin: 6pt 0 18pt; border-radius: 6pt; }
        hr { border: 0; border-top: 0.6pt solid #d8d5ca; margin: 0 0 18pt; }
        p { margin: 0 0 13pt; orphans: 3; widows: 3; }
        .source { margin-top: 22pt; padding-top: 10pt; border-top: 0.6pt solid #d8d5ca; color: #687277; font: 9pt -apple-system, BlinkMacSystemFont, sans-serif; overflow-wrap: anywhere; }
        </style></head><body><article>
        <h1>\(title)</h1>
        <div class="meta">\(sourceName) \(byline)</div>
        \(reference)
        \(image)
        <hr />
        \(paragraphs)
        <div class="source">Original: \(sourceURL)</div>
        </article></body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func safeFilename(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let pieces = value.components(separatedBy: disallowed)
        let joined = pieces.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((joined.isEmpty ? "Reader Article" : joined).prefix(80))
    }
}

enum ReaderRemoteImageLoader {
    static let maximumResponseBytes = 12_000_000
    static let maximumSourcePixels = 40_000_000
    static let maximumDecodedDimension = 2_048

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        return configuration
    }

    static func load(
        from url: URL?,
        referringPageURL: URL? = nil,
        configuration: URLSessionConfiguration = makeConfiguration()
    ) async -> Data? {
        guard let url, await ReaderRemoteURLPolicy.allows(url) else {
            return nil
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.httpShouldHandleCookies = false
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        if let referringPageURL,
           await ReaderRemoteURLPolicy.allows(referringPageURL),
           let referrer = referrerOrigin(for: referringPageURL) {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }

        let downloaded = await BoundedReaderImageDownload.load(
            request: request,
            configuration: configuration,
            maximumBytes: maximumResponseBytes
        )
        guard let downloaded else { return nil }
        return normalizedJPEG(from: downloaded)
    }

    private static func referrerOrigin(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        components.path = "/"
        return components.url?.absoluteString
    }

    static func isAcceptableSourcePixelSize(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0,
              width <= maximumSourcePixels,
              height <= maximumSourcePixels else {
            return false
        }
        return width <= maximumSourcePixels / height
    }

    static func normalizedJPEG(from data: Data) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as NSDictionary?,
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
              isAcceptableSourcePixelSize(width: width, height: height) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: NSNumber(value: true),
            kCGImageSourceCreateThumbnailWithTransform: NSNumber(value: true),
            kCGImageSourceThumbnailMaxPixelSize: NSNumber(value: maximumDecodedDimension),
            kCGImageSourceShouldCacheImmediately: NSNumber(value: true)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let destinationOptions = [
            kCGImageDestinationLossyCompressionQuality: NSNumber(value: 0.82)
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, destinationOptions)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

private enum ReaderRemoteURLPolicy {
    static func allows(_ url: URL) async -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !isClearlyLocalHostname(host) else {
            return false
        }

        return await Task.detached(priority: .utility) {
            resolvesOnlyToPublicAddresses(host)
        }.value
    }

    private static func isClearlyLocalHostname(_ host: String) -> Bool {
        host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal")
            || host.hasSuffix(".lan")
            || host.hasSuffix(".home")
    }

    private static func resolvesOnlyToPublicAddresses(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            return false
        }
        defer { freeaddrinfo(first) }

        var foundAddress = false
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current?.pointee {
            guard let address = info.ai_addr else { return false }
            foundAddress = true
            if !isPublic(address: address, family: info.ai_family) {
                return false
            }
            current = info.ai_next
        }
        return foundAddress
    }

    private static func isPublic(address: UnsafePointer<sockaddr>, family: Int32) -> Bool {
        switch family {
        case AF_INET:
            let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            return isPublicIPv4(ipv4)
        case AF_INET6:
            let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) }
            }
            guard bytes.count == 16 else { return false }
            let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 }
                && bytes[10] == 0xff
                && bytes[11] == 0xff
            if isIPv4Mapped {
                let ipv4 = UInt32(bytes[12]) << 24
                    | UInt32(bytes[13]) << 16
                    | UInt32(bytes[14]) << 8
                    | UInt32(bytes[15])
                return isPublicIPv4(ipv4)
            }
            let isUnspecified = bytes.allSatisfy { $0 == 0 }
            let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            let isUniqueLocal = (bytes[0] & 0xfe) == 0xfc
            let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
            let isMulticast = bytes[0] == 0xff
            return !(isUnspecified || isLoopback || isUniqueLocal || isLinkLocal || isMulticast)
        default:
            return false
        }
    }

    private static func isPublicIPv4(_ address: UInt32) -> Bool {
        let first = UInt8((address >> 24) & 0xff)
        let second = UInt8((address >> 16) & 0xff)
        return !(first == 0
            || first == 10
            || first == 127
            || (first == 100 && (64...127).contains(second))
            || (first == 169 && second == 254)
            || (first == 172 && (16...31).contains(second))
            || (first == 192 && second == 168)
            || (first == 198 && (18...19).contains(second))
            || first >= 224)
    }
}

private final class BoundedReaderImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private var received = Data()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var session: URLSession?
    private var finished = false

    private init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    static func load(
        request: URLRequest,
        configuration: URLSessionConfiguration,
        maximumBytes: Int
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            let delegate = BoundedReaderImageDownload(maximumBytes: maximumBytes)
            delegate.continuation = continuation

            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .utility
            let session = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: queue
            )
            delegate.session = session
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse,
              (200..<400).contains(response.statusCode),
              response.mimeType?.lowercased().hasPrefix("image/") == true,
              response.expectedContentLength <= 0 || response.expectedContentLength <= maximumBytes else {
            dataTask.cancel()
            completionHandler(.cancel)
            finish(with: nil)
            return
        }

        if response.expectedContentLength > 0 {
            received.reserveCapacity(Int(response.expectedContentLength))
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url else {
            completionHandler(nil)
            finish(with: nil)
            return
        }
        Task {
            let allowed = await ReaderRemoteURLPolicy.allows(url)
            completionHandler(allowed ? request : nil)
            if !allowed {
                finish(with: nil)
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard data.count <= maximumBytes,
              received.count <= maximumBytes - data.count else {
            dataTask.cancel()
            finish(with: nil)
            return
        }
        received.append(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        finish(with: error == nil ? received : nil)
    }

    private func finish(with data: Data?) {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: data)
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
    }
}

private final class ReaderPDFPageRenderer: UIPrintPageRenderer {
    private let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

    override var paperRect: CGRect { pageBounds }
    override var printableRect: CGRect { pageBounds.insetBy(dx: 48, dy: 48) }
}

enum ReaderPDFExportError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        "The Reader PDF could not be created."
    }
}
