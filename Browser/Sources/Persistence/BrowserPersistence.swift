import Foundation

protocol BrowserPersisting {
    func load() throws -> BrowserSnapshot?
    func save(_ snapshot: BrowserSnapshot) throws
}
struct BrowserPersistence: BrowserPersisting {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? baseURL
            .appendingPathComponent("PersonalBrowser", isDirectory: true)
            .appendingPathComponent("browser-state.json", isDirectory: false)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> BrowserSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(BrowserSnapshot.self, from: Data(contentsOf: fileURL))
    }

    func save(_ snapshot: BrowserSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
