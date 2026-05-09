import SwiftUI

// MARK: - SectionHeader

/// Section title with optional accessory view on the trailing side.
/// Grows with Dynamic Type — no fixed heights.
struct SectionHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            Spacer()

            accessory()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.xs)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}
