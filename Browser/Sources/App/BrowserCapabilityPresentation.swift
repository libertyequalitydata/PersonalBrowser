import Foundation

enum BrowserCapabilityPresentation {
    static let sourceBuildSummary = "This source build intentionally omits Apple-managed browser capabilities. They do not transfer with source code and require a distributor's own app identity, Apple approval where applicable, signing, and physical-device verification."
    static let defaultBrowserTitle = "Default Browser"
    static let defaultBrowserSummary = "Not included. Registering web URL schemes does not make this source build an approved iPhone default browser."
    static let passkeyTitle = "Browser passkeys"
    static let passkeyDisabledStatus = "Unavailable in this source build"
    static let passkeySummary = "Website passkey authorization requires a separately configured Apple browser capability and supported iOS version."
    static let addToHomeScreenTitle = "Add to Home Screen"
    static let addToHomeScreenSummary = "This source build does not include the separately approved Apple browser capability required to add a website directly to the Home Screen."
    static let addToHomeScreenAlert = "Add to Home Screen is intentionally unavailable in this source build. A distributor must configure and verify the required Apple browser capability in its own signed app."
}
