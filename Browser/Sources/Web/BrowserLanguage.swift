import Foundation

enum BrowserLanguage {
    static var preferredIdentifiers: [String] {
        normalizedIdentifiers(Locale.preferredLanguages)
    }

    static func normalizedIdentifiers(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()

        return identifiers.compactMap { identifier in
            let normalized = identifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")

            guard !normalized.isEmpty else { return nil }

            let comparisonKey = normalized.lowercased()
            guard seen.insert(comparisonKey).inserted else { return nil }
            return normalized
        }
    }

    static func primaryLanguageCode(for identifiers: [String] = Locale.preferredLanguages) -> String? {
        normalizedIdentifiers(identifiers)
            .first?
            .split(separator: "-")
            .first
            .map { String($0).lowercased() }
    }

    static func acceptLanguageHeader(for identifiers: [String] = Locale.preferredLanguages) -> String? {
        let languages = Array(normalizedIdentifiers(identifiers).prefix(6))
        guard !languages.isEmpty else { return nil }

        return languages.enumerated().map { index, language in
            guard index > 0 else { return language }
            let quality = max(1.0 - (Double(index) * 0.1), 0.5)
            return "\(language);q=\(String(format: "%.1f", quality))"
        }.joined(separator: ", ")
    }

    static func request(
        for url: URL,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> URLRequest {
        var request = URLRequest(url: url)
        if let header = acceptLanguageHeader(for: preferredLanguages) {
            request.setValue(header, forHTTPHeaderField: "Accept-Language")
        }
        return request
    }
}
