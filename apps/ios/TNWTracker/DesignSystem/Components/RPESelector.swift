import SwiftUI

// MARK: - RIRScale

/// The effort options for a user maximum N ("Máximo de RIR", 1–10, default 4):
/// 0, 1, …, N−1 and "N+". The format keeps `rir` as 0–10; choosing "N+" stores N,
/// and a stored value above N is shown as "N+" without being rewritten.
struct RIRScale {
    enum Option: Hashable {
        case value(Int)
        case atLeast(Int)

        var label: String {
            switch self {
            case let .value(value): "\(value)"
            case let .atLeast(value): "\(value)+"
            }
        }
    }

    /// `@AppStorage` key of the user setting. It is not part of the training data format.
    static let storageKey = "settings.rirMaximum"
    static let defaultMaximum = 4
    static let allowedMaximums = 1 ... 10

    let maximum: Int

    init(maximum: Int) {
        self.maximum = min(max(maximum, Self.allowedMaximums.lowerBound), Self.allowedMaximums.upperBound)
    }

    var options: [Option] {
        (0 ..< maximum).map(Option.value) + [.atLeast(maximum)]
    }

    /// The value stored when the user picks `option`.
    func rir(for option: Option) -> Int {
        switch option {
        case let .value(value), let .atLeast(value): value
        }
    }

    /// The option shown as selected for a stored value. Read-only: a value above
    /// the maximum shows as "N+" and keeps its stored value.
    func option(for rir: Int?) -> Option? {
        guard let rir else { return nil }
        return rir >= maximum ? .atLeast(maximum) : .value(rir)
    }
}

// MARK: - RIRSelector

// The file keeps its old name: renaming it needs a project.pbxproj change.

/// Reps in reserve (RIR) selector over a `RIRScale`: 0 … N−1 and "N+".
/// Each tap target is ≥ 44pt (HIG compliant).
/// NO fixed height on the container — grows with Dynamic Type.
struct RIRSelector: View {
    @Binding var selection: Int?
    let scale: RIRScale

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Spacing.sm) {
            ForEach(scale.options, id: \.self) { option in
                rirButton(option: option)
            }
        }
    }

    @ViewBuilder
    private func rirButton(option: RIRScale.Option) -> some View {
        let isSelected = scale.option(for: selection) == option
        Button {
            selection = scale.rir(for: option)
        } label: {
            Text(verbatim: option.label)
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
        .accessibilityLabel(accessibilityLabel(for: option))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func accessibilityLabel(for option: RIRScale.Option) -> Text {
        switch option {
        case let .value(value): Text("rir.value \(value)")
        case let .atLeast(value): Text("rir.at-least \(value)")
        }
    }
}

#Preview("RIRSelector") {
    @Previewable @State var rir: Int?
    VStack(spacing: Spacing.md) {
        RIRSelector(selection: $rir, scale: RIRScale(maximum: RIRScale.defaultMaximum))
        Text(rir.map { "RIR: \($0)" } ?? "No selection")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
