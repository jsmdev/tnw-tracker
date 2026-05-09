import SwiftUI

// MARK: - GlassToolbar ViewModifier

/// Applies glass scroll edge effect to navigation bars.
/// Use via .glassToolbar() on NavigationStack or root TabView.
struct GlassToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

extension View {
    func glassToolbar() -> some View {
        modifier(GlassToolbarModifier())
    }
}
