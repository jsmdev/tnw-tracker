import SwiftUI

// MARK: - Scroll-away title

// A screen whose name is part of its scrolling content (a sheet with a photo
// above the name, a summary) shows that name in the navigation bar once it has
// scrolled under the bar, fading in as the system's own titles do (AC6).
//
// Usage: `.scrollAwayTitleContent()` on the scroll view's content stack,
// `.scrollAwayTitleHeader(bottom: $nameBottom)` on the name, and
// `.scrollAwayTitle(below: nameBottom, isScrolledAway: $showsBarTitle)` on the
// scroll view; then a `BarTitle` in the toolbar's `.principal` placement.

private let contentSpace = "scrollAwayTitle.content"

extension View {
    /// The coordinate space the name's position is measured in.
    func scrollAwayTitleContent() -> some View {
        coordinateSpace(.named(contentSpace))
    }

    /// Measures where the name ends in the content.
    func scrollAwayTitleHeader(bottom: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(contentSpace)).maxY
        } action: { maxY in
            bottom.wrappedValue = maxY
        }
    }

    /// Sets `isScrolledAway` once the content has scrolled past `nameBottom`,
    /// that is, once the name is under the navigation bar.
    func scrollAwayTitle(below nameBottom: CGFloat, isScrolledAway: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { geometry in
            nameBottom > 0 && geometry.contentOffset.y + geometry.contentInsets.top > nameBottom
        } action: { _, scrolledAway in
            withAnimation(.easeInOut(duration: 0.2)) {
                isScrolledAway.wrappedValue = scrolledAway
            }
        }
    }
}

// MARK: - BarTitle

/// The name in the navigation bar: absent, also for VoiceOver, while the name
/// in the content is on screen; it fades in and out. Like the system's inline
/// titles, it keeps the bar's text size.
struct BarTitle: View {
    let text: Text
    let isShown: Bool
    let identifier: String

    var body: some View {
        ZStack {
            if isShown {
                text
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifier)
                    .transition(.opacity)
            }
        }
    }
}
