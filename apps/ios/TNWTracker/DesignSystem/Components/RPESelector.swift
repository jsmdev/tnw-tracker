import SwiftUI

// MARK: - RPESelector

/// Visual RPE (Rate of Perceived Exertion) selector, values 1–10.
/// Grid of 10 buttons — each tap target is ≥ 44pt (HIG compliant).
/// NO fixed height on the container — grows with Dynamic Type.
struct RPESelector: View {
    @Binding var selection: Int?

    private let values = Array(1 ... 10)

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: Spacing.sm) {
            ForEach(values, id: \.self) { value in
                rpeButton(value: value)
            }
        }
    }

    @ViewBuilder
    private func rpeButton(value: Int) -> some View {
        let isSelected = selection == value
        Button {
            selection = value
        } label: {
            Text(verbatim: "\(value)")
                .font(.headline)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .frame(minWidth: 44, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("rpe.value \(value)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("RPESelector") {
    @Previewable @State var rpe: Int? = nil
    VStack(spacing: Spacing.md) {
        RPESelector(selection: $rpe)
        Text(rpe.map { "RPE: \($0)" } ?? "No selection")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
