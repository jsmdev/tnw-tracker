import SwiftUI

// MARK: - SetDisplayData

/// Lightweight value type for SetCard — decoupled from SwiftData models.
/// Feature views map their domain models to this struct before passing to SetCard.
struct SetDisplayData: Identifiable {
    let id: UUID
    let setNumber: Int
    let reps: Int
    let weight: Double
    let rir: Int?
    var warmup = false
}

// MARK: - SetCard

/// Card displaying a single logged set (reps, weight, RIR, warm-up mark).
/// NO glass, no fixed height — grows with Dynamic Type.
struct SetCard: View {
    let set: SetDisplayData

    var body: some View {
        HStack(spacing: Spacing.md) {
            Group {
                if set.warmup {
                    Text("set.warmup-short")
                } else {
                    Text(verbatim: "\(set.setNumber)")
                }
            }
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
                if set.warmup {
                    Text("set.warmup-badge")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let rir = set.rir {
                VStack(spacing: 2) {
                    Text("set.rir")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(rir)")
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
        SetCard(set: SetDisplayData(id: UUID(), setNumber: 1, reps: 5, weight: 100, rir: 2, warmup: true))
        SetCard(set: SetDisplayData(id: UUID(), setNumber: 2, reps: 5, weight: 102.5, rir: 1))
        SetCard(set: SetDisplayData(id: UUID(), setNumber: 3, reps: 3, weight: 105, rir: nil))
    }
    .padding()
}
