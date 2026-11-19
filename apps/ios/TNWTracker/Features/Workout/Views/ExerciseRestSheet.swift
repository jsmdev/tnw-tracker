import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseRestSheetItem

/// Identifiable wrapper driving `.sheet(item:)`: the setting in force when opened.
struct ExerciseRestSheetItem: Identifiable {
    let setting: ExerciseSetting
    var id: UUID { setting.exerciseId }
}

// MARK: - ExerciseRestSheet

/// "Descanso entre series" of one exercise: a toggle and a duration.
/// Every change is handed to `onChange` at once, so it is saved for this and
/// every later session. Turning the rest off keeps the duration.
struct ExerciseRestSheet: View {
    let onChange: (ExerciseSetting) -> Void

    @State private var setting: ExerciseSetting
    @Environment(\.dismiss) private var dismiss

    init(item: ExerciseRestSheetItem, onChange: @escaping (ExerciseSetting) -> Void) {
        _setting = State(initialValue: item.setting)
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("exercise-rest.title", isOn: $setting.restEnabled)
                        .accessibilityIdentifier(AXID.ExerciseRest.enabledToggle)
                    RestDurationControl(
                        seconds: $setting.restSeconds,
                        durationIdentifier: AXID.ExerciseRest.durationLabel,
                        decreaseIdentifier: AXID.ExerciseRest.decreaseButton,
                        increaseIdentifier: AXID.ExerciseRest.increaseButton
                    )
                    .disabled(!setting.restEnabled)
                } footer: {
                    Text("exercise-rest.footer")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier(AXID.ExerciseRest.doneButton)
                }
            }
        }
        .onChange(of: setting) { _, newValue in
            onChange(newValue)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ExerciseRestSheet") {
    ExerciseRestSheet(
        item: ExerciseRestSheetItem(setting: ExerciseSetting(exerciseId: UUID(), restSeconds: 90)),
        onChange: { _ in }
    )
}
#endif
