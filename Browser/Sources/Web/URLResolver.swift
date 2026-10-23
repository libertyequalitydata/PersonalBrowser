import Foundation

enum URLResolver {
    static func resolve(
        _ input: String,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicitURL = URL(string: trimmed),
           let scheme = explicitURL.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return explicitURL
        }

        if looksLikeHost(trimmed), let url = URL(string: "https://\(trimmed)") {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            BrowserLanguage.primaryLanguageCode(for: preferredLanguages).map {
                URLQueryItem(name: "hl", value: $0)
            }
        ].compactMap { $0 }
        return components?.url
    }

    private static func looksLikeHost(_ value: String) -> Bool {
        guard !value.contains(where: { $0.isWhitespace }) else { return false }
        return value.contains(".") || value == "localhost"
    }

    static func conventionalFaviconURL(for pageURL: URL?) -> URL? {
        guard let pageURL,
              ["http", "https"].contains(pageURL.scheme?.lowercased() ?? ""),
              var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
