import SwiftUI

@main
struct BrowserApp: App {
    @StateObject private var store = BrowserStore()
    @StateObject private var mediaPlayback = BrowserMediaPlaybackController()
    @StateObject private var documentViewer = BrowserDocumentViewerController()
    @StateObject private var transcription = BrowserTranscriptionController()

    init() {
        BrowserPasskeySupport.prepareIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            BrowserRootView()
                .environmentObject(store)
                .environmentObject(mediaPlayback)
                .environmentObject(documentViewer)
                .environmentObject(transcription)
                .preferredColorScheme(.light)
        }
    }
}
