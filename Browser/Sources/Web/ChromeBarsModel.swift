import SwiftUI

@MainActor
final class ChromeBarsModel: ObservableObject {
    static let collapseDistance: CGFloat = 54

    @Published private(set) var progress: CGFloat = 1
    private(set) var isPinnedHidden = false

    private var baseOffset: CGFloat = 0
    private var baseProgress: CGFloat = 1
    private var lastOffset: CGFloat = 0
    private var lastDirection: ScrollDirection = .none
    private var isUserScrolling = false

    func beginScroll(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) {
        guard !isPinnedHidden else { return }
        guard canCollapse(contentHeight: contentHeight, viewportHeight: viewportHeight) else {
            show(animated: false)
            return
        }

        isUserScrolling = true
        baseOffset = offset
        lastOffset = offset
        baseProgress = progress
        lastDirection = .none

        if isAtBottom(offset: offset, contentHeight: contentHeight, viewportHeight: viewportHeight),
           progress == 0 {
            show()
        }
    }

    func updateScroll(
        offset: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        isZooming: Bool
    ) {
        guard !isPinnedHidden else { return }
        guard canCollapse(contentHeight: contentHeight, viewportHeight: viewportHeight),
              !isZooming else {
            show(animated: false)
            return
        }

        if offset <= 0 {
            show(animated: false)
            baseOffset = offset
            baseProgress = 1
            lastOffset = offset
            return
        }

        guard isUserScrolling else { return }

        let delta = offset - lastOffset

        // Collapsing the browser bars changes the WebView's height. When the
        // page is pinned to its bottom edge, UIKit compensates by changing the
        // content offset. Treating that synthetic adjustment as user input
        // creates a feedback loop that makes the rubber-band state oscillate.
        // Chromium's fullscreen model ignores the same at/past-bottom updates
        // while its WebView is being resized.
        if isAtBottom(
            offset: offset,
            contentHeight: contentHeight,
            viewportHeight: viewportHeight
        ) {
            return
        }

        let direction: ScrollDirection = delta > 0.25 ? .down : delta < -0.25 ? .up : .none

        if direction != .none,
           lastDirection != .none,
           direction != lastDirection {
            baseOffset = lastOffset
            baseProgress = progress
        }

        if direction != .none {
            lastDirection = direction
        }

        let totalDelta = offset - baseOffset
        progress = min(1, max(0, baseProgress - totalDelta / Self.collapseDistance))
        lastOffset = offset
    }

    func endScroll() {
        guard !isPinnedHidden else { return }
        guard isUserScrolling else { return }
        isUserScrolling = false
        let target: CGFloat = progress >= 0.5 ? 1 : 0
        withAnimation(.timingCurve(0, 0, 0.2, 0.1, duration: 0.2)) {
            progress = target
        }
        baseProgress = target
        lastDirection = .none
    }

    func show(animated: Bool = true) {
        guard !isPinnedHidden else { return }
        isUserScrolling = false
        lastDirection = .none
        baseProgress = 1
        if animated {
            withAnimation(.timingCurve(0, 0, 0.2, 0.1, duration: 0.2)) {
                progress = 1
            }
        } else {
            progress = 1
        }
    }

    func hideUntilRevealed(animated: Bool = true) {
        isPinnedHidden = true
        isUserScrolling = false
        lastDirection = .none
        baseProgress = 0
        if animated {
            withAnimation(.timingCurve(0, 0, 0.2, 0.1, duration: 0.2)) {
                progress = 0
            }
        } else {
            progress = 0
        }
    }

    func reveal(animated: Bool = true) {
        isPinnedHidden = false
        show(animated: animated)
    }

    private func canCollapse(contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        contentHeight > viewportHeight + Self.collapseDistance
    }

    private func isAtBottom(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        offset + viewportHeight >= contentHeight - 1
    }
}

private enum ScrollDirection {
    case up
    case down
    case none
}
