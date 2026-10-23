import PDFKit
import UIKit
import XCTest
@testable import PersonalBrowser

@MainActor
final class ReaderPDFExportTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ReaderImageURLProtocol.response = nil
        ReaderImageURLProtocol.body = Data()
        ReaderImageURLProtocol.capturedRequest = nil
    }

    func testRemoteReaderImageLoaderUsesEphemeralCookieFreeBoundedConfiguration() {
        let configuration = ReaderRemoteImageLoader.makeConfiguration()

        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 12)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 15)
        XCTAssertEqual(ReaderRemoteImageLoader.maximumResponseBytes, 12_000_000)
        XCTAssertEqual(ReaderRemoteImageLoader.maximumSourcePixels, 40_000_000)
        XCTAssertEqual(ReaderRemoteImageLoader.maximumDecodedDimension, 2_048)
    }

    func testRemoteReaderImageLoaderRejectsOversizedDeclaredResponse() async throws {
        ReaderImageURLProtocol.response = HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://93.184.216.34/hero.jpg")),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "image/jpeg",
                "Content-Length": "12000001"
            ]
        )
        ReaderImageURLProtocol.body = Data(repeating: 1, count: 32)
        let configuration = ReaderRemoteImageLoader.makeConfiguration()
        configuration.protocolClasses = [ReaderImageURLProtocol.self]

        let result = await ReaderRemoteImageLoader.load(
            from: try XCTUnwrap(URL(string: "https://93.184.216.34/hero.jpg")),
            configuration: configuration
        )

        XCTAssertNil(result)
    }

    func testRemoteReaderImageLoaderRejectsExcessivePixelDimensions() {
        XCTAssertTrue(ReaderRemoteImageLoader.isAcceptableSourcePixelSize(width: 8_000, height: 5_000))
        XCTAssertFalse(ReaderRemoteImageLoader.isAcceptableSourcePixelSize(width: 8_001, height: 5_000))
        XCTAssertFalse(ReaderRemoteImageLoader.isAcceptableSourcePixelSize(width: Int.max, height: 2))
    }

    func testRemoteReaderImageLoaderDownsamplesBeforeJPEGEncoding() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 3_000, height: 2_000),
            format: format
        )
        let sourceData = renderer.jpegData(withCompressionQuality: 0.4) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_000, height: 2_000))
        }

        let normalized = try XCTUnwrap(ReaderRemoteImageLoader.normalizedJPEG(from: sourceData))
        let image = try XCTUnwrap(UIImage(data: normalized))

        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 2_048)
    }

    func testRemoteReaderImageLoaderSendsImageAcceptAndPublicReferrerOrigin() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let imageData = UIGraphicsImageRenderer(
            size: CGSize(width: 400, height: 240),
            format: format
        ).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 240))
        }
        let imageURL = try XCTUnwrap(URL(string: "https://93.184.216.34/hero.jpg"))
        ReaderImageURLProtocol.response = HTTPURLResponse(
            url: imageURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "image/jpeg",
                "Content-Length": "\(imageData.count)"
            ]
        )
        ReaderImageURLProtocol.body = imageData
        let configuration = ReaderRemoteImageLoader.makeConfiguration()
        configuration.protocolClasses = [ReaderImageURLProtocol.self]

        let result = await ReaderRemoteImageLoader.load(
            from: imageURL,
            referringPageURL: try XCTUnwrap(URL(string: "https://93.184.216.34/article/path?query=1")),
            configuration: configuration
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(ReaderImageURLProtocol.capturedRequest?.value(forHTTPHeaderField: "Referer"), "https://93.184.216.34/")
        XCTAssertTrue(
            ReaderImageURLProtocol.capturedRequest?
                .value(forHTTPHeaderField: "Accept")?
                .contains("image/*") == true
        )
    }

    func testReaderPDFMarkupUsesWhiteCanvasAndEmbedsMainImage() throws {
        let document = ReaderDocument(
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/article")),
            title: "Image Article",
            text: "Article body",
            previewImageURL: try XCTUnwrap(URL(string: "https://example.com/hero.jpg")),
            capturedIdentityID: UUID(),
            captureKind: .readableCapture
        )
        let imageData = Data([0xff, 0xd8, 0xff, 0xd9])

        let markup = ReaderPDFExporter.markup(for: document, imageData: imageData)

        XCTAssertTrue(markup.contains("html, body, article { background: #ffffff; }"))
        XCTAssertTrue(markup.contains("class=\"hero\""))
        XCTAssertTrue(markup.contains("data:image/jpeg;base64,\(imageData.base64EncodedString())"))
    }

    func testRemoteReaderImageLoaderRejectsLocalNetworkURL() async throws {
        let result = await ReaderRemoteImageLoader.load(
            from: try XCTUnwrap(URL(string: "http://127.0.0.1/private-image.jpg"))
        )

        XCTAssertNil(result)
    }

    func testRemoteReaderImageLoaderRejectsIPv4MappedLoopbackURL() async throws {
        let result = await ReaderRemoteImageLoader.load(
            from: try XCTUnwrap(URL(string: "http://[::ffff:127.0.0.1]/private-image.jpg"))
        )

        XCTAssertNil(result)
    }

    func testReaderPDFExportCreatesReadableMultipageFile() async throws {
        let paragraph = "Reader PDF export keeps the simplified article content readable and suitable for Files."
        let document = ReaderDocument(
            sourceURL: try XCTUnwrap(URL(string: "https://example.com/article")),
            title: "A Reader Article",
            author: "Example Author",
            siteName: "Example",
            text: Array(repeating: paragraph, count: 90).joined(separator: "\n\n"),
            capturedIdentityID: UUID(),
            captureKind: .readableCapture
        )

        let fileURL = try await ReaderPDFExporter.export(document)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let data = try Data(contentsOf: fileURL)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let pdf = try XCTUnwrap(PDFDocument(url: fileURL))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let extracted = (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(extracted.contains("A Reader Article"))
        XCTAssertTrue(extracted.contains("Example Author"))
        XCTAssertTrue(extracted.contains("Reader PDF export"))
        XCTAssertTrue(extracted.contains("https://example.com/article"))
    }
}

private final class ReaderImageURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: HTTPURLResponse?
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var deliveredBodyBytes = 0
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    private var deliveryWorkItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.deliveredBodyBytes = 0
        Self.capturedRequest = request
        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.deliveryWorkItem?.isCancelled == false else {
                return
            }
            Self.deliveredBodyBytes = Self.body.count
            self.client?.urlProtocol(self, didLoad: Self.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        deliveryWorkItem = workItem
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    override func stopLoading() {
        deliveryWorkItem?.cancel()
        deliveryWorkItem = nil
    }
}
