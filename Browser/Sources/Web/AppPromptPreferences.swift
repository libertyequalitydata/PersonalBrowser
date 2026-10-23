import Foundation
import Combine

final class AppPromptPreferences {
    static let shared = AppPromptPreferences()

    private let defaults: UserDefaults
    private let key = "blockedAppPromptHosts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isBlocked(url: URL?) -> Bool {
        guard let host = Self.normalizedHost(from: url) else { return false }
        return blockedHosts.contains(host)
    }

    func setBlocked(_ blocked: Bool, url: URL?) {
        guard let host = Self.normalizedHost(from: url) else { return }
        var hosts = blockedHosts
        if blocked {
            hosts.insert(host)
        } else {
            hosts.remove(host)
        }
        defaults.set(Array(hosts).sorted(), forKey: key)
    }

    static func normalizedHost(from url: URL?) -> String? {
        guard var host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }
        return host
    }

    private var blockedHosts: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}

enum ExternalAppLinkChoice: String, CaseIterable, Codable, Identifiable {
    case stayInBrowser
    case openApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stayInBrowser:
            return "Stay in Browser"
        case .openApp:
            return "Open App"
        }
    }
}

struct ExternalAppLinkRequest: Identifiable, Equatable {
    let id = UUID()
    let serviceKey: String
    let serviceName: String
    let destinationURL: URL
    let webFallbackURL: URL?

    var openActionTitle: String {
        switch serviceKey {
        case "email": return "Open Mail"
        case "phone": return "Open Phone"
        case "messages": return "Open Messages"
        case "maps": return "Open Maps"
        case "app-store": return "Open App Store"
        default: return "Open \(serviceName)"
        }
    }
}

struct ExternalAppLinkPreferenceRecord: Identifiable, Equatable {
    let serviceKey: String
    let serviceName: String
    let choice: ExternalAppLinkChoice

    var id: String { serviceKey }
}

final class ExternalAppLinkPreferences: ObservableObject {
    static let shared = ExternalAppLinkPreferences()

    @Published private(set) var choices: [String: ExternalAppLinkChoice]

    private let defaults: UserDefaults
    private let key = "externalAppLinkChoices"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        choices = stored.reduce(into: [:]) { result, entry in
            if let choice = ExternalAppLinkChoice(rawValue: entry.value) {
                result[entry.key] = choice
            }
        }
    }

    func choice(for serviceKey: String) -> ExternalAppLinkChoice? {
        choices[serviceKey]
    }

    func setChoice(_ choice: ExternalAppLinkChoice, for serviceKey: String) {
        choices[serviceKey] = choice
        persist()
    }

    func removeChoice(for serviceKey: String) {
        choices.removeValue(forKey: serviceKey)
        persist()
    }

    func resetAll() {
        choices.removeAll()
        persist()
    }

    var records: [ExternalAppLinkPreferenceRecord] {
        choices.map { key, choice in
            ExternalAppLinkPreferenceRecord(
                serviceKey: key,
                serviceName: ExternalAppLinkResolver.displayName(for: key),
                choice: choice
            )
        }
        .sorted { $0.serviceName.localizedCaseInsensitiveCompare($1.serviceName) == .orderedAscending }
    }

    private func persist() {
        defaults.set(choices.mapValues(\.rawValue), forKey: key)
    }
}

enum ExternalAppLinkResolver {
    private static let internalSchemes: Set<String> = [
        "about", "blob", "data", "javascript", "browser-test"
    ]

    private static let serviceByScheme: [String: (key: String, name: String)] = [
        "linkedin": ("linkedin", "LinkedIn"),
        "instagram": ("instagram", "Instagram"),
        "fb": ("facebook", "Facebook"),
        "facebook": ("facebook", "Facebook"),
        "twitter": ("x", "X"),
        "x": ("x", "X"),
        "reddit": ("reddit", "Reddit"),
        "youtube": ("youtube", "YouTube"),
        "tiktok": ("tiktok", "TikTok"),
        "pinterest": ("pinterest", "Pinterest"),
        "spotify": ("spotify", "Spotify"),
        "mailto": ("email", "Email"),
        "tel": ("phone", "Phone"),
        "telprompt": ("phone", "Phone"),
        "sms": ("messages", "Messages"),
        "maps": ("maps", "Maps"),
        "itms-apps": ("app-store", "App Store"),
        "itms-appss": ("app-store", "App Store")
    ]

    static func request(for destinationURL: URL?, sourceURL: URL?) -> ExternalAppLinkRequest? {
        guard let destinationURL,
              let scheme = destinationURL.scheme?.lowercased(),
              !internalSchemes.contains(scheme) else { return nil }

        if ["http", "https"].contains(scheme) {
            guard isAppStoreURL(destinationURL) else { return nil }
            return ExternalAppLinkRequest(
                serviceKey: "app-store",
                serviceName: "App Store",
                destinationURL: destinationURL,
                webFallbackURL: destinationURL
            )
        }

        let service = serviceByScheme[scheme] ?? (scheme, displayName(for: scheme))
        return ExternalAppLinkRequest(
            serviceKey: service.key,
            serviceName: service.name,
            destinationURL: destinationURL,
            webFallbackURL: webFallback(
                for: service.key,
                destinationURL: destinationURL,
                sourceURL: sourceURL
            )
        )
    }

    static func displayName(for serviceKey: String) -> String {
        switch serviceKey {
        case "linkedin": return "LinkedIn"
        case "instagram": return "Instagram"
        case "facebook": return "Facebook"
        case "x": return "X"
        case "reddit": return "Reddit"
        case "youtube": return "YouTube"
        case "tiktok": return "TikTok"
        case "pinterest": return "Pinterest"
        case "spotify": return "Spotify"
        case "email": return "Email"
        case "phone": return "Phone"
        case "messages": return "Messages"
        case "maps": return "Maps"
        case "app-store": return "App Store"
        default:
            return serviceKey
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    private static func isAppStoreURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "apps.apple.com" || host == "itunes.apple.com"
    }

    private static func webFallback(
        for serviceKey: String,
        destinationURL: URL,
        sourceURL: URL?
    ) -> URL? {
        if let embedded = embeddedWebURL(in: destinationURL) {
            return embedded
        }

        let destinationText = destinationURL.absoluteString.lowercased()
        if serviceKey == "linkedin",
           destinationText.contains("login") || destinationText.contains("signin") || destinationText.contains("auth") {
            return URL(string: "https://www.linkedin.com/login")
        }

        if sourceMatches(serviceKey: serviceKey, url: sourceURL) {
            return sourceURL
        }

        let fallbackByService: [String: String] = [
            "linkedin": "https://www.linkedin.com/",
            "instagram": "https://www.instagram.com/",
            "facebook": "https://www.facebook.com/",
            "x": "https://x.com/",
            "reddit": "https://www.reddit.com/",
            "youtube": "https://www.youtube.com/",
            "tiktok": "https://www.tiktok.com/",
            "pinterest": "https://www.pinterest.com/",
            "spotify": "https://open.spotify.com/"
        ]
        return fallbackByService[serviceKey].flatMap(URL.init(string:))
    }

    private static func embeddedWebURL(in url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let candidateNames = Set(["url", "href", "link", "fallback_url", "browser_url"])
        return components.queryItems?
            .first(where: { candidateNames.contains($0.name.lowercased()) })?
            .value
            .flatMap(URL.init(string:))
            .flatMap { candidate in
                ["http", "https"].contains(candidate.scheme?.lowercased() ?? "") ? candidate : nil
            }
    }

    private static func sourceMatches(serviceKey: String, url: URL?) -> Bool {
        guard let host = AppPromptPreferences.normalizedHost(from: url) else { return false }
        switch serviceKey {
        case "linkedin": return host == "linkedin.com" || host.hasSuffix(".linkedin.com")
        case "instagram": return host == "instagram.com" || host.hasSuffix(".instagram.com")
        case "facebook": return host == "facebook.com" || host.hasSuffix(".facebook.com")
        case "x": return host == "x.com" || host == "twitter.com" || host.hasSuffix(".x.com") || host.hasSuffix(".twitter.com")
        case "reddit": return host == "reddit.com" || host.hasSuffix(".reddit.com")
        case "youtube": return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
        case "tiktok": return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
        case "pinterest": return host == "pinterest.com" || host.hasSuffix(".pinterest.com")
        case "spotify": return host == "spotify.com" || host.hasSuffix(".spotify.com")
        default: return false
        }
    }
}

final class SessionRetentionPreferences {
    static let shared = SessionRetentionPreferences()

    private let defaults: UserDefaults
    private let key = "keptSignInSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func keepsSession(url: URL?) -> Bool {
        guard let host = AppPromptPreferences.normalizedHost(from: url) else { return false }
        return keptSites.contains(host)
    }

    func setKeepsSession(_ keepsSession: Bool, url: URL?) {
        guard let host = AppPromptPreferences.normalizedHost(from: url) else { return }
        var sites = keptSites
        if keepsSession {
            sites.insert(host)
        } else {
            sites.remove(host)
        }
        defaults.set(Array(sites).sorted(), forKey: key)
    }

    private var keptSites: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
