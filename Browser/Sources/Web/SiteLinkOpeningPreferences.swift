import Combine
import Foundation

final class SiteLinkOpeningPreferences: ObservableObject {
    static let shared = SiteLinkOpeningPreferences()

    @Published private(set) var policies: [String: BrowserLinkOpeningPolicy]

    private let defaults: UserDefaults
    private let storageKey = "siteExternalLinkOpeningPolicies"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        policies = stored.keys.sorted { left, right in
            if left.count == right.count { return left < right }
            return left.count < right.count
        }.reduce(into: [:]) { result, storedKey in
            guard let storedValue = stored[storedKey] else { return }
            let policy: BrowserLinkOpeningPolicy?
            if storedValue == "previewPanel" {
                policy = .subtab
            } else {
                policy = BrowserLinkOpeningPolicy(rawValue: storedValue)
            }
            if let policy, policy != .followWebsite {
                let normalizedKey = Self.siteKey(
                    for: URL(string: "https://\(storedKey)")
                ) ?? storedKey
                if result[normalizedKey] == nil {
                    result[normalizedKey] = policy
                }
            }
        }
        if policies.mapValues(\.rawValue) != stored {
            defaults.set(policies.mapValues(\.rawValue), forKey: storageKey)
        }
    }

    func policy(for url: URL?) -> BrowserLinkOpeningPolicy {
        guard let key = Self.siteKey(for: url) else { return .followWebsite }
        return policies[key] ?? .followWebsite
    }

    func hasStoredPolicy(for url: URL?) -> Bool {
        guard let key = Self.siteKey(for: url) else { return false }
        return policies[key] != nil
    }

    func setPolicy(_ policy: BrowserLinkOpeningPolicy, for url: URL?) {
        guard let key = Self.siteKey(for: url) else { return }
        if policy == .followWebsite {
            policies[key] = nil
        } else {
            policies[key] = policy
        }
        defaults.set(
            policies.mapValues(\.rawValue),
            forKey: storageKey
        )
    }

    static func isExternalLink(from sourceURL: URL?, to destinationURL: URL?) -> Bool {
        guard let sourceKey = siteKey(for: sourceURL),
              let destinationKey = siteKey(for: destinationURL) else { return false }
        return sourceKey != destinationKey
    }

    static func siteKey(for url: URL?) -> String? {
        guard let url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              var host = url.host?.lowercased(),
              !host.isEmpty else { return nil }

        if host.hasPrefix("www."), host.count > 4 {
            host.removeFirst(4)
        }

        if host == "notebooklm.google.com" {
            host = "notebook.google.com"
        }

        if hostScopedServiceSuffixes.contains(where: {
            host == $0 || host.hasSuffix(".\($0)")
        }) {
            return host
        }

        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }

        let finalTwo = labels.suffix(2).joined(separator: ".")
        if multiLabelPublicSuffixes.contains(finalTwo) {
            return labels.suffix(3).joined(separator: ".")
        }
        return finalTwo
    }

    private static let multiLabelPublicSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk",
        "com.au", "net.au", "org.au",
        "co.nz", "org.nz",
        "co.jp", "ne.jp",
        "com.br", "com.mx", "co.in"
    ]

    private static let hostScopedServiceSuffixes: Set<String> = [
        "github.io",
        "pages.dev",
        "vercel.app",
        "netlify.app",
        "appspot.com",
        "azurewebsites.net"
    ]

}

enum SiteWrappedExternalLinkResolver {
    static func destination(for requestedURL: URL, sourceURL: URL?) -> URL {
        let sourceSite = SiteLinkOpeningPreferences.siteKey(for: sourceURL)
        let requestedSite = SiteLinkOpeningPreferences.siteKey(for: requestedURL)

        if sourceSite == "linkedin.com",
           requestedSite == "linkedin.com",
           recognizedLinkedInOutboundPaths.contains(normalizedPath(requestedURL.path)),
           let destination = queryDestination(
               in: requestedURL,
               names: linkedInDestinationQueryNames
           ) {
            return destination
        }

        if sourceSite == "facebook.com",
           requestedSite == "facebook.com",
           recognizedFacebookOutboundHosts.contains(requestedURL.host?.lowercased() ?? ""),
           normalizedPath(requestedURL.path) == "/l.php",
           let destination = queryDestination(
               in: requestedURL,
               names: facebookDestinationQueryNames
           ) {
            return destination
        }

        return requestedURL
    }

    private static func normalizedPath(_ path: String) -> String {
        let lowered = path.lowercased()
        guard lowered.count > 1, lowered.hasSuffix("/") else { return lowered }
        return String(lowered.dropLast())
    }

    private static func externalWebURL(from value: String) -> URL? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<3 {
            if let url = URL(string: candidate),
               ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
               url.host?.isEmpty == false,
               url.user == nil,
               url.password == nil {
                return url
            }
            guard let decoded = candidate.removingPercentEncoding,
                  decoded != candidate else { break }
            candidate = decoded
        }
        return nil
    }

    private static func queryDestination(in requestedURL: URL, names: Set<String>) -> URL? {
        guard let components = URLComponents(url: requestedURL, resolvingAgainstBaseURL: false),
              let encodedDestination = components.queryItems?.first(where: {
                  names.contains($0.name.lowercased())
              })?.value,
              let destination = externalWebURL(from: encodedDestination),
              SiteLinkOpeningPreferences.isExternalLink(
                  from: requestedURL,
                  to: destination
              ) else {
            return nil
        }
        return destination
    }

    private static let recognizedLinkedInOutboundPaths: Set<String> = [
        "/safety/go",
        "/redir/redirect"
    ]

    private static let linkedInDestinationQueryNames: Set<String> = [
        "url",
        "target",
        "destination"
    ]

    private static let recognizedFacebookOutboundHosts: Set<String> = [
        "l.facebook.com",
        "lm.facebook.com"
    ]

    private static let facebookDestinationQueryNames: Set<String> = [
        "u",
        "url",
        "href"
    ]
}
