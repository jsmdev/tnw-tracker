import SwiftUI
import TNWTrackerKit

// MARK: - SetLogFormState

/// Local form state for the set logging sheet.
/// Inline — no separate file needed (anti-overengineering rule).
struct SetLogFormState {
    var reps: Int = 0
    var weight: Double = 0.0
    var rpe: Int?
    var isWarmup: Bool = false

    /// Valid when reps > 0 and, if RPE is set, it's in range 1–10.
    var isValid: Bool {
        guard reps > 0 else { return false }
        if let rpe {
            return rpe >= 1 && rpe <= 10
        }
        return true
    }
}

// MARK: - SetLogSheetItem

/// Identifiable wrapper driving `.sheet(item:)`.
struct SetLogSheetItem: Identifiable {
    let id: UUID
    let exercise: WorkoutExercise
    let nextSetNumber: Int
}

// MARK: - SetLogSheet

/// Sheet for logging a single set: reps + weight + RPE + warmup toggle.
/// REQ-AWV-02 (numeric keyboard), REQ-AWV-03 (RPE selector).
struct SetLogSheet: View {
    let item: SetLogSheetItem
    let onSave: (SetLogFormState) -> Void
    let onCancel: () -> Void

    @State private var formState = SetLogFormState()
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case reps, weight
    }

    var body: some View {
        NavigationStack {
            Form {
                setInfoSection
                rpeSection
                optionsSection
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
        } header: {
            Text("set-log.set-section-header \(item.nextSetNumber)")
        }
    }

    private var rpeSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("set-log.rpe-label")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                RPESelector(selection: $formState.rpe)
                    .padding(.vertical, Spacing.xs)
            }
        } header: {
            Text("set-log.rpe-section-header")
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle(isOn: $formState.isWarmup) {
                Text("set-log.warmup-toggle")
            }
        }
    }
}

// MARK: - Preview

#Preview("SetLogSheet") {
    @Previewable @State var item: SetLogSheetItem? = SetLogSheetItem(
        id: UUID(),
        exercise: WorkoutExercise(workoutId: UUID(), exerciseId: UUID(), orderIndex: 0),
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
