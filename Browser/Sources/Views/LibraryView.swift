import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var mediaPlayback: BrowserMediaPlaybackController
    @EnvironmentObject private var documentViewer: BrowserDocumentViewerController
    @EnvironmentObject private var transcription: BrowserTranscriptionController
    let onBack: () -> Void
    let onViewOriginal: (ReaderDocument) -> Void
    @State private var selectedReadingItemID: UUID?
    @State private var showingArchived = false
    @State private var previewedDocumentURL: URL?

    var body: some View {
        ZStack {
            NavigationStack {
                Group {
                    if displayedEntries.isEmpty {
                        ContentUnavailableView {
                            Label(
                                showingArchived ? "Archive empty" : "Library empty",
                                systemImage: showingArchived ? "archivebox" : "text.book.closed"
                            )
                        } description: {
                            Text(
                                showingArchived
                                    ? "Archived articles and files will appear here."
                                    : "Articles and downloaded files you add for later will appear here."
                            )
                        }
                    } else {
                        List {
                            ForEach(displayedEntries) { entry in
                                libraryRow(entry)
                                    .listRowBackground(Color.readerCanvas)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .background(Color.readerCanvas)
                .navigationTitle(showingArchived ? "Archived" : "Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(Color.readerCanvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: navigateBack) {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingArchived.toggle()
                            }
                        } label: {
                            Image(systemName: showingArchived ? "archivebox.fill" : "archivebox")
                        }
                        .accessibilityLabel(showingArchived ? "Show Library" : "Show Archived")
                        .accessibilityValue(showingArchived ? "Archived items shown" : "Active Library shown")
                    }
                }
            }
            .opacity(selectedReadingItemID == nil ? 1 : 0)
            .allowsHitTesting(selectedReadingItemID == nil)

            if let selectedItem {
                ReaderView(
                    document: selectedItem.document,
                    readingItemID: showingArchived ? nil : selectedItem.id,
                    onBack: navigateBack,
                    onArchive: showingArchived ? nil : { archiveAndAdvance(from: selectedItem.id) },
                    onViewOriginal: { onViewOriginal(selectedItem.document) }
                )
                .id(selectedItem.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: ReadingListNavigationMotion.articleInsertionEdge)
                            .combined(with: .opacity),
                        removal: .move(edge: ReadingListNavigationMotion.articleBackRemovalEdge)
                            .combined(with: .opacity)
                    )
                )
                .zIndex(1)
            }
        }
        .environment(\.colorScheme, .light)
        .background(Color.readerCanvas)
        .background {
            ReaderPageSwipeBackGesture(action: navigateBack)
        }
        .quickLookPreview($previewedDocumentURL)
    }

    private func navigateBack() {
        if selectedReadingItemID == nil {
            onBack()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedReadingItemID = nil
            }
        }
    }

    private var selectedItem: ReadingItem? {
        guard let selectedReadingItemID else { return nil }
        return store.readingList.first(where: { $0.id == selectedReadingItemID })
    }

    private var displayedEntries: [LibraryDisplayEntry] {
        let articles = (showingArchived ? store.archivedReadingList : store.activeReadingList)
            .map(LibraryDisplayEntry.article)
        let artifacts = (showingArchived ? store.archivedLibraryArtifacts : store.activeLibraryArtifacts)
            .map(LibraryDisplayEntry.artifact)
        return (articles + artifacts).sorted { $0.date > $1.date }
    }

    private func archiveAndAdvance(from itemID: UUID) {
        let nextItemID = ReadingListSequence.nextItemID(
            after: itemID,
            in: store.activeReadingList.map(\.id)
        )

        withAnimation(.easeInOut(duration: 0.28)) {
            store.archiveReadingItem(itemID)
            selectedReadingItemID = nextItemID
        }
    }

    private func readingRow(_ item: ReadingItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.document.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.browserInk)
                    .lineLimit(2)

                Text(item.document.contentSnippet)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(item.document.siteName ?? item.document.sourceURL.host ?? "Source")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let imageURL = readingImageURL(for: item) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    case .empty:
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.browserInk.opacity(0.05))
                            .frame(width: 96, height: 72)
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func libraryRow(_ entry: LibraryDisplayEntry) -> some View {
        switch entry {
        case .article(let item):
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    selectedReadingItemID = item.id
                }
            } label: {
                readingRow(item)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                archiveButton {
                    store.archiveReadingItem(item.id)
                }
            }

        case .artifact(let artifact):
            Button {
                open(artifact)
            } label: {
                artifactRow(artifact)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                archiveButton {
                    store.setLibraryArtifactArchived(artifact.id, archived: !showingArchived)
                }
            }
            .contextMenu {
                if artifact.kind == .audio || artifact.kind == .video {
                    Button {
                        transcribe(artifact)
                    } label: {
                        Label("Transcribe Audio", systemImage: "waveform.and.magnifyingglass")
                    }
                }

                Button {
                    store.setLibraryArtifactArchived(artifact.id, archived: !showingArchived)
                } label: {
                    Label(showingArchived ? "Restore" : "Archive", systemImage: showingArchived ? "arrow.uturn.backward" : "archivebox")
                }

                Button(role: .destructive) {
                    store.removeLibraryArtifact(artifact.id)
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
            }
        }
    }

    private func archiveButton(action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                action()
            }
        } label: {
            Label(showingArchived ? "Restore" : "Archive", systemImage: showingArchived ? "arrow.uturn.backward" : "archivebox")
        }
        .tint(Color.browserAccent)
    }

    private func artifactRow(_ artifact: LibraryArtifact) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: artifact.kind.systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(artifact.kind == .pdf ? Color.red : Color.browserAccent)
                .frame(width: 42, height: 48)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(artifact.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.browserInk)
                    .lineLimit(2)

                Text(artifactSubtitle(artifact))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(artifact.sourceURL.host ?? "Local file")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if transcription.activeArtifactID == artifact.id {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 12)
            }
        }
        .padding(.vertical, 10)
    }

    private func open(_ artifact: LibraryArtifact) {
        guard let url = store.libraryFileURL(for: artifact) else {
            store.showNotice("Library file is missing", systemImage: "exclamationmark.triangle.fill", isFailure: true)
            return
        }
        switch artifact.kind {
        case .audio:
            mediaPlayback.play(url: url, title: artifact.title, kind: .audio, libraryArtifactID: artifact.id)
        case .video:
            mediaPlayback.play(url: url, title: artifact.title, kind: .video, libraryArtifactID: artifact.id)
        case .pdf:
            documentViewer.presentPDF(url: url, title: artifact.title)
        case .document:
            previewedDocumentURL = url
        }
    }

    private func artifactSubtitle(_ artifact: LibraryArtifact) -> String {
        let transcript = artifact.transcript?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return transcript?.isEmpty == false ? transcript! : artifact.kind.title
    }

    private func transcribe(_ artifact: LibraryArtifact) {
        guard let url = store.libraryFileURL(for: artifact) else { return }
        transcription.transcribe(artifact: artifact, url: url, store: store)
    }

    private func readingImageURL(for item: ReadingItem) -> URL? {
        item.document.previewImageURL ?? store.tabs.first(where: {
            $0.url == item.document.sourceURL
        })?.previewImageURL
    }
}

private enum LibraryDisplayEntry: Identifiable {
    case article(ReadingItem)
    case artifact(LibraryArtifact)

    var id: String {
        switch self {
        case .article(let item): "article-\(item.id.uuidString)"
        case .artifact(let item): "artifact-\(item.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .article(let item): item.document.capturedAt
        case .artifact(let item): item.addedAt
        }
    }
}

enum ReadingListNavigationMotion {
    static let articleInsertionEdge: Edge = .trailing
    static let articleBackRemovalEdge: Edge = .trailing
}

enum ReaderBackGesture {
    static func shouldNavigateBack(translation: CGSize) -> Bool {
        translation.width > 72 &&
            abs(translation.width) > abs(translation.height)
    }
}

enum ReaderArchiveGesture {
    static func isTrackingArchive(translation: CGSize) -> Bool {
        translation.width < 0 &&
            abs(translation.width) > abs(translation.height)
    }

    static func shouldArchive(translation: CGSize) -> Bool {
        translation.width < -72 &&
            abs(translation.width) > abs(translation.height)
    }
}

enum ReadingListSequence {
    static func nextItemID(after itemID: UUID, in itemIDs: [UUID]) -> UUID? {
        guard let index = itemIDs.firstIndex(of: itemID) else { return nil }
        let remaining = itemIDs.filter { $0 != itemID }
        guard !remaining.isEmpty else { return nil }
        return remaining[min(index, remaining.count - 1)]
    }
}

private struct ReaderPageSwipeBackGesture: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> ReaderPageSwipeHostingView {
        ReaderPageSwipeHostingView(action: action)
    }

    func updateUIView(_ view: ReaderPageSwipeHostingView, context: Context) {
        view.action = action
    }

    static func dismantleUIView(_ view: ReaderPageSwipeHostingView, coordinator: ()) {
        view.removeRecognizer()
    }
}

private final class ReaderPageSwipeHostingView: UIView, UIGestureRecognizerDelegate {
    var action: () -> Void
    private weak var gestureHost: UIView?
    private lazy var recognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        return recognizer
    }()

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installRecognizerIfNeeded()
    }

    func removeRecognizer() {
        gestureHost?.removeGestureRecognizer(recognizer)
        gestureHost = nil
    }

    private func installRecognizerIfNeeded() {
        guard let window, gestureHost !== window else { return }
        removeRecognizer()
        window.addGestureRecognizer(recognizer)
        gestureHost = window
    }

    @objc private func handleSwipe(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let point = recognizer.translation(in: recognizer.view)
        let translation = CGSize(width: point.x, height: point.y)
        guard ReaderBackGesture.shouldNavigateBack(translation: translation) else { return }
        action()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: pan.view)
        return velocity.x > 0 && abs(velocity.x) > abs(velocity.y) * 1.15
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

}
