import PDFKit
import SwiftUI

struct BrowserPDFItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let title: String
}

@MainActor
final class BrowserDocumentViewerController: ObservableObject {
    @Published var presentedPDF: BrowserPDFItem?

    func presentPDF(url: URL, title: String) {
        presentedPDF = BrowserPDFItem(url: url, title: title)
    }

    func dismiss() {
        presentedPDF = nil
    }
}

struct BrowserPDFViewerScreen: View {
    let item: BrowserPDFItem
    let onDismiss: () -> Void
    @State private var controlsVisible = true
    @State private var pageIndex = 0
    @State private var pageCount = 0
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            BrowserPDFView(
                url: item.url,
                pageIndex: $pageIndex,
                pageCount: $pageCount
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { toggleControls() }

            if controlsVisible {
                VStack {
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.62), in: Circle())
                        }
                        .accessibilityLabel("Close PDF")

                        Spacer()

                        Text(pageCount > 0 ? "\(pageIndex + 1) of \(pageCount)" : "PDF")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color.black.opacity(0.62), in: Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 48)
                        .background(Color.black.opacity(0.68), in: Capsule())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!controlsVisible)
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
        .animation(.easeOut(duration: 0.16), value: controlsVisible)
    }

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
    }
}

private struct BrowserPDFView: UIViewRepresentable {
    let url: URL
    @Binding var pageIndex: Int
    @Binding var pageCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(pageIndex: $pageIndex, pageCount: $pageCount)
    }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .black
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.displaysPageBreaks = false
        view.usePageViewController(true, withViewOptions: nil)
        view.document = PDFDocument(url: url)
        context.coordinator.attach(to: view)
        context.coordinator.update(from: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        context.coordinator.update(from: view)
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        @Binding private var pageIndex: Int
        @Binding private var pageCount: Int
        private weak var view: PDFView?
        private var observer: NSObjectProtocol?

        init(pageIndex: Binding<Int>, pageCount: Binding<Int>) {
            _pageIndex = pageIndex
            _pageCount = pageCount
        }

        func attach(to view: PDFView) {
            self.view = view
            observer = NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: view,
                queue: .main
            ) { [weak self] _ in
                self?.update(from: view)
            }
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            view = nil
        }

        func update(from view: PDFView) {
            let count = view.document?.pageCount ?? 0
            let index = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.pageCount = count
                self?.pageIndex = max(0, index)
            }
        }
    }
}
