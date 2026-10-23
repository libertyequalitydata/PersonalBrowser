import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var store: BrowserStore
    let document: ReaderDocument
    var readingItemID: UUID?
    let onBack: () -> Void
    var onArchive: (() -> Void)? = nil
    let onViewOriginal: () -> Void

    @State private var fontSize: CGFloat = 19
    @StateObject private var footerVisibility = ReaderActionVisibilityModel()
    @GestureState private var archiveDragOffset: CGFloat = 0
    @GestureState private var archiveSwipeActive = false
    @State private var isCommittingArchive = false
    @State private var sharePayload: ReaderSharePayload?
    @State private var shareError: String?
    @State private var isExportingPDF = false

    var body: some View {
        ZStack {
            if onArchive != nil {
                archiveRevealSurface
            }

            articleSurface
                .offset(x: articleHorizontalOffset)
                .opacity(1 - min(abs(articleHorizontalOffset) / CGFloat(700), 0.18))
        }
        .background(Color.readerCanvas)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.86), value: archiveDragOffset)
        .sheet(item: $sharePayload) { payload in
            ReaderShareActivityView(payload: payload)
        }
        .alert("Reader PDF", isPresented: shareErrorPresented) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "The Reader PDF could not be created.")
        }
    }

    private var articleSurface: some View {
        ScrollView {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: ReaderScrollOffsetPreferenceKey.self,
                        value: -proxy.frame(in: .named("reading-list-article-scroll")).minY
                    )
            }
            .frame(height: 0)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(document.title)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundStyle(Color.browserInk)

                    HStack(spacing: 8) {
                        Text(document.siteName ?? document.sourceURL.host ?? "Source")
                        if let author = document.author { Text("•"); Text(author) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if document.captureKind == .referenceOnly {
                        Label("Reference-only capture", systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }

                ReaderHeroImage(url: document.previewImageURL)

                Divider()

                Text(document.text)
                    .font(.system(size: fontSize, design: .serif))
                    .foregroundStyle(Color.browserInk)
                    .lineSpacing(7)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 112)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(archiveSwipeActive || isCommittingArchive)
        .coordinateSpace(name: "reading-list-article-scroll")
        .onPreferenceChange(ReaderScrollOffsetPreferenceKey.self) {
            footerVisibility.update(offset: $0)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .updating($archiveDragOffset) { value, state, _ in
                    guard onArchive != nil,
                          ReaderArchiveGesture.isTrackingArchive(translation: value.translation) else { return }
                    state = max(value.translation.width, -180)
                }
                .updating($archiveSwipeActive) { value, state, _ in
                    state = onArchive != nil && ReaderArchiveGesture.isTrackingArchive(
                        translation: value.translation
                    )
                }
                .onChanged {
                    if !ReaderArchiveGesture.isTrackingArchive(translation: $0.translation) {
                        footerVisibility.updateDrag(translationHeight: $0.translation.height)
                    }
                }
                .onEnded {
                    guard ReaderArchiveGesture.shouldArchive(translation: $0.translation) else { return }
                    commitArchive()
                }
        )
        .background(Color.readerCanvas)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            readerHeader
        }
        .overlay(alignment: .bottom) {
            readerFooter
                .offset(y: footerVisibility.isVisible ? 0 : 88)
                .opacity(footerVisibility.isVisible ? 1 : 0)
                .allowsHitTesting(footerVisibility.isVisible)
                .animation(.easeOut(duration: 0.18), value: footerVisibility.isVisible)
        }
        .onAppear { footerVisibility.reset() }
    }

    private var articleHorizontalOffset: CGFloat {
        isCommittingArchive ? -UIScreen.main.bounds.width : archiveDragOffset
    }

    private var archiveRevealSurface: some View {
        Color.browserAccent
            .ignoresSafeArea()
            .overlay(alignment: .trailing) {
                VStack(spacing: 8) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Archive")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.trailing, 28)
                .opacity(min(max(abs(articleHorizontalOffset) / CGFloat(72), 0), 1))
            }
    }

    private func commitArchive() {
        guard let onArchive, !isCommittingArchive else { return }
        withAnimation(.easeIn(duration: 0.18)) {
            isCommittingArchive = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
            onArchive()
        }
    }

    private var readerHeader: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Library")

            Spacer()

            Menu {
                Button("Smaller text") { fontSize = max(15, fontSize - 2) }
                Button("Larger text") { fontSize = min(30, fontSize + 2) }
            } label: {
                Text("AA")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Text size")
        }
        .foregroundStyle(Color.browserInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.readerCanvas)
    }

    private var readerFooter: some View {
        HStack(spacing: 4) {
            if let readingItemID {
                footerButton("Archive as Read", systemImage: "checkmark.circle") {
                    if onArchive != nil {
                        commitArchive()
                    } else {
                        store.archiveReadingItem(readingItemID)
                    }
                }
            }

            Menu {
                Button {
                    exportPDF()
                } label: {
                    Label("Share Reader PDF", systemImage: "doc.richtext")
                }
                .disabled(isExportingPDF)

                Button {
                    sharePayload = .originalLink(document.sourceURL)
                } label: {
                    Label("Share Original Link", systemImage: "link")
                }
            } label: {
                footerIcon("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)

            footerButton("View Original", systemImage: "safari") {
                onViewOriginal()
            }
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.browserAccent.opacity(0.14))
        }
        .shadow(color: Color.readerCanvas.opacity(0.9), radius: 16, y: 6)
        .padding(.horizontal, 24)
        .padding(.vertical, ReaderFloatingLayout.edgePadding)
    }

    private func footerButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            footerIcon(label, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func footerIcon(_ label: String, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.browserInk)
            .frame(width: 48, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }

    private func exportPDF() {
        guard !isExportingPDF else { return }
        isExportingPDF = true
        Task {
            defer { isExportingPDF = false }
            do {
                sharePayload = .exportedPDF(try await ReaderPDFExporter.export(document))
            } catch {
                shareError = error.localizedDescription
            }
        }
    }

    private var shareErrorPresented: Binding<Bool> {
        Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )
    }
}

enum ReaderFloatingLayout {
    static let edgePadding: CGFloat = 8

    static func inlineBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        max(safeAreaBottom, 0) + edgePadding
    }
}

struct ReaderHeroImage: View {
    let url: URL?

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .empty:
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.browserInk.opacity(0.04))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay { ProgressView().controlSize(.small) }
                case .failure:
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}
