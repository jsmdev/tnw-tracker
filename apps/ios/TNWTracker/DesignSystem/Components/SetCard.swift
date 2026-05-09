import SwiftUI

// MARK: - SetDisplayData

/// Lightweight value type for SetCard — decoupled from SwiftData models.
/// Feature views map their domain models to this struct before passing to SetCard.
struct SetDisplayData: Identifiable {
    let id: UUID
    let setNumber: Int
    let reps: Int
    let weight: Double
    let rpe: Int?
}

// MARK: - SetCard

/// Card displaying a single logged set (reps, weight, RPE).
/// NO glass, no fixed height — grows with Dynamic Type.
struct SetCard: View {
    let set: SetDisplayData

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text(verbatim: "\(set.setNumber)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .center)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text("set.reps \(set.reps)")
                        .font(.body)
                        .fontWeight(.medium)

                    Text(verbatim: "·")
                        .foregroundStyle(.tertiary)

                    Text(set.weight, format: .number)
                        .font(.body)
                        + Text(" kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let rpe = set.rpe {
                VStack(spacing: 2) {
                    Text("set.rpe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(rpe)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .accessibilityElement(children: .combine)
    }
}

#Preview("SetCard") {
    VStack(spacing: Spacing.sm) {
        SetCard(set: SetDisplayData(id: UUID(), setNumber: 1, reps: 5, weight: 100, rpe: 8))
        SetCard(set: SetDisplayData(id: UUID(), setNumber: 2, reps: 5, weight: 102.5, rpe: 9))
        SetCard(set: SetDisplayData(id: UUID(), setNumber: 3, reps: 3, weight: 105, rpe: nil))
    }
    .padding()
}
