import SwiftUI

// MARK: - Card

/// Generic card container. NO glass — uses .regularMaterial background.
/// Content grows with Dynamic Type — no fixed height.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Spacing.md)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

#Preview("Card") {
    Card {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("card.sample-title")
                .font(.headline)
            Text("card.sample-body")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
    .padding()
}
