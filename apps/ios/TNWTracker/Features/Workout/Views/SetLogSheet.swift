import SwiftUI
import TNWTrackerKit

// MARK: - SetLogFormState

/// Local form state for the set logging sheet.
/// Inline — no separate file needed (anti-overengineering rule).
///
/// Effort is asked and stored as reps in reserve (format field `rir`, 0–10),
/// with no conversion (D2). The selector offers 0 … N−1 and "N+" (`RIRScale`).
struct SetLogFormState {
    /// Empty (`nil`) until the user types, so the field shows its placeholder.
    var reps: Int?
    var weight: Double?
    var rir: Int?
    var warmup = false

    /// Valid when reps > 0 and, if RIR is set, it's in range 0–10.
    var isValid: Bool {
        guard let reps, reps > 0 else { return false }
        if let rir {
            return (0 ... 10).contains(rir)
        }
        return true
    }

    /// The weight to log: none when empty or 0 (bodyweight exercises).
    var loggedWeightKilograms: Double? {
        guard let weight, weight > 0 else { return nil }
        return weight
    }
}

// MARK: - SetLogSheetItem

/// Identifiable wrapper driving `.sheet(item:)`.
struct SetLogSheetItem: Identifiable {
    let id: UUID
    let exerciseId: UUID
    let nextSetNumber: Int
}

// MARK: - SetLogSheet

/// Sheet for logging a single set: reps + weight + warm-up toggle + RIR.
/// REQ-AWV-02 (numeric keyboard), REQ-AWV-03 (effort selector, as RIR).
struct SetLogSheet: View {
    let item: SetLogSheetItem
    let onSave: (SetLogFormState) -> Void
    let onCancel: () -> Void

    @State private var formState = SetLogFormState()
    @AppStorage(RIRScale.storageKey) private var rirMaximum = RIRScale.defaultMaximum
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case reps, weight
    }

    var body: some View {
        NavigationStack {
            Form {
                setInfoSection
                rirSection
            }
            .navigationTitle(Text("set-log.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("set-log.cancel-button", action: onCancel)
                        .accessibilityIdentifier(AXID.SetLog.cancelButton)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("set-log.save-button") {
                        onSave(formState)
                    }
                    .disabled(!formState.isValid)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(AXID.SetLog.saveButton)
                }
            }
        }
        .presentationSizing(.form)
        // Opens with the keyboard up on reps, the first thing to type.
        .onAppear { focusedField = .reps }
    }

    // MARK: - Sections

    private var setInfoSection: some View {
        Section {
            HStack {
                Text("set-log.reps-label")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0", value: $formState.reps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .reps)
                    .frame(minWidth: 60)
                    .accessibilityLabel("set-log.reps-label")
                    .accessibilityIdentifier(AXID.SetLog.repsField)
            }

            HStack {
                Text("set-log.weight-label")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("0.0", value: $formState.weight, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .weight)
                    .frame(minWidth: 80)
                    .accessibilityLabel("set-log.weight-label")
                    .accessibilityIdentifier(AXID.SetLog.weightField)
                Text("set-log.weight-unit")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Toggle("set-log.warmup-toggle", isOn: $formState.warmup)
                .accessibilityIdentifier(AXID.SetLog.warmupToggle)
        } header: {
            Text("set-log.set-section-header \(item.nextSetNumber)")
        }
    }

    private var rirSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("set-log.rir-label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                RIRSelector(selection: $formState.rir, scale: RIRScale(maximum: rirMaximum))
                    .padding(.vertical, Spacing.xs)
            }
        } header: {
            Text("set-log.rir-section-header")
        }
    }
}

// MARK: - Preview

#Preview("SetLogSheet") {
    @Previewable @State var item: SetLogSheetItem? = SetLogSheetItem(
        id: UUID(),
        exerciseId: UUID(),
        nextSetNumber: 1
    )

    Color.clear
        .sheet(item: $item) { sheetItem in
            SetLogSheet(
                item: sheetItem,
                onSave: { _ in item = nil },
                onCancel: { item = nil }
            )
        }
}
