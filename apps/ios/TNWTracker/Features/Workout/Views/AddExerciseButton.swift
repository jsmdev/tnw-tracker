import SwiftUI
import TNWTrackerKit

/// "Añadir ejercicio" (#137 S5): opens the account's exercises; a row makes
/// that exercise the current one of the session in progress.
struct AddExerciseButton: View {
    @Environment(AppEnvironment.self) private var appEnv
    let coordinator: ActiveWorkoutCoordinator

    @State private var showPicker = false

    var body: some View {
        SecondaryButton(title: "active-workout.add-exercise") {
            showPicker = true
        }
        .accessibilityIdentifier(AXID.ActiveWorkout.addExerciseButton)
        .sheet(isPresented: $showPicker) {
            picker
        }
    }

    private var picker: some View {
        NavigationStack {
            ExerciseListView(exerciseRepository: appEnv.exerciseRepository) { exerciseId in
                coordinator.addExercise(exerciseId)
                showPicker = false
            }
            .navigationTitle(Text("active-workout.add-exercise"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        showPicker = false
                    }
                    .accessibilityIdentifier(AXID.ActiveWorkout.exercisePickerCancelButton)
                }
            }
        }
    }
}
