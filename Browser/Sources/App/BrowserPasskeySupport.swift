import AuthenticationServices
import Combine
import Foundation
import UIKit

@MainActor
final class BrowserPasskeySupport: ObservableObject {
    enum AuthorizationStatus: Equatable {
        case disabled
        case unavailable
        case notDetermined
        case authorized
        case denied
    }

    static let shared = BrowserPasskeySupport()
    nonisolated static let authorizationBuildFlag = "BrowserPasskeyAuthorizationEnabled"

    @Published private(set) var authorizationStatus: AuthorizationStatus = .disabled

    private var credentialManager: AnyObject?

    nonisolated static var isAuthorizationEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: authorizationBuildFlag) as? Bool ?? false
    }

    var statusDescription: String {
        switch authorizationStatus {
        case .disabled:
            return BrowserCapabilityPresentation.passkeyDisabledStatus
        case .unavailable:
            return "Requires iOS 17.4 or later"
        case .notDetermined:
            return "Permission has not been decided"
        case .authorized:
            return "Available to websites in Browser"
        case .denied:
            return "Permission is off in iOS Settings"
        }
    }

    private init() {}

    static func prepareIfEnabled() {
        shared.prepareIfEnabled()
    }

    func prepareIfEnabled() {
        guard Self.isAuthorizationEnabled else {
            authorizationStatus = .disabled
            credentialManager = nil
            return
        }
        guard #available(iOS 17.4, *) else {
            authorizationStatus = .unavailable
            credentialManager = nil
            return
        }

        let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        credentialManager = manager
        apply(manager.authorizationStateForPlatformCredentials)
        if manager.authorizationStateForPlatformCredentials == .notDetermined {
            requestAuthorization()
        }
    }

    func requestAuthorization() {
        guard Self.isAuthorizationEnabled else {
            authorizationStatus = .disabled
            return
        }
        guard #available(iOS 17.4, *) else {
            authorizationStatus = .unavailable
            return
        }

        let manager: ASAuthorizationWebBrowserPublicKeyCredentialManager
        if let retained = credentialManager as? ASAuthorizationWebBrowserPublicKeyCredentialManager {
            manager = retained
        } else {
            manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
            credentialManager = manager
        }

        switch manager.authorizationStateForPlatformCredentials {
        case .authorized, .denied:
            apply(manager.authorizationStateForPlatformCredentials)
        case .notDetermined:
            manager.requestAuthorizationForPublicKeyCredentials { [weak self] state in
                Task { @MainActor in
                    self?.apply(state)
                }
            }
        @unknown default:
            authorizationStatus = .unavailable
        }
    }

    func refreshAuthorizationStatus() {
        guard Self.isAuthorizationEnabled else {
            authorizationStatus = .disabled
            return
        }
        guard #available(iOS 17.4, *),
              let manager = credentialManager as? ASAuthorizationWebBrowserPublicKeyCredentialManager else {
            prepareIfEnabled()
            return
        }
        apply(manager.authorizationStateForPlatformCredentials)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @available(iOS 17.4, *)
    private func apply(
        _ state: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState
    ) {
        switch state {
        case .authorized:
            authorizationStatus = .authorized
        case .denied:
            authorizationStatus = .denied
        case .notDetermined:
            authorizationStatus = .notDetermined
        @unknown default:
            authorizationStatus = .unavailable
        }
    }
}
