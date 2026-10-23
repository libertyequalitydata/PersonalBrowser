import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let page: WebPage

    func makeUIView(context: Context) -> WKWebView {
        page.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
