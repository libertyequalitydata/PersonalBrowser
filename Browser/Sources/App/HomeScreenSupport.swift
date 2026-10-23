import SwiftUI
import UIKit
import WebKit

enum BrowserEntitlementStatus {
    static let addToHomeScreenBuildFlag = "BrowserAddToHomeScreenEnabled"

    static var canAddToHomeScreen: Bool {
        Bundle.main.object(forInfoDictionaryKey: addToHomeScreenBuildFlag) as? Bool ?? false
    }
}

struct WebsiteHomeScreenActivityView: UIViewControllerRepresentable {
    let webView: WKWebView

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [webView],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
