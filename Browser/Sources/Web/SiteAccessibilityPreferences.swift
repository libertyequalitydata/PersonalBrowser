import Combine
import Foundation

struct SiteAccessibilitySupport: Equatable {
    let domainKey: String
    let displayName: String
    let supportsBottomNavigation: Bool

    static func resolve(for url: URL?) -> SiteAccessibilitySupport? {
        guard let host = AppPromptPreferences.normalizedHost(from: url) else { return nil }

        if host == "facebook.com" || host.hasSuffix(".facebook.com") {
            return SiteAccessibilitySupport(
                domainKey: "facebook.com",
                displayName: "Facebook",
                supportsBottomNavigation: true
            )
        }

        return nil
    }
}

final class SiteAccessibilityPreferences: ObservableObject {
    static let shared = SiteAccessibilityPreferences()

    @Published private(set) var bottomNavigationDomains: Set<String>

    private let defaults: UserDefaults
    private let bottomNavigationKey = "siteAccessibilityBottomNavigationDomains"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bottomNavigationDomains = Set(defaults.stringArray(forKey: bottomNavigationKey) ?? [])
    }

    func isBottomNavigationEnabled(for url: URL?) -> Bool {
        guard let support = SiteAccessibilitySupport.resolve(for: url),
              support.supportsBottomNavigation else { return false }
        return bottomNavigationDomains.contains(support.domainKey)
    }

    func setBottomNavigationEnabled(_ enabled: Bool, for url: URL?) {
        guard let support = SiteAccessibilitySupport.resolve(for: url),
              support.supportsBottomNavigation else { return }

        if enabled {
            bottomNavigationDomains.insert(support.domainKey)
        } else {
            bottomNavigationDomains.remove(support.domainKey)
        }
        defaults.set(Array(bottomNavigationDomains).sorted(), forKey: bottomNavigationKey)
    }
}
