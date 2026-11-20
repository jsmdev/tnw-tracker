import Foundation

// MARK: - AXID

/// Accessibility identifiers for UI test automation.
/// Format: AXID.<Screen>.<element> where element is lowerCamelCase.
/// NOT localized. Stable across copy changes.
/// Use .accessibilityIdentifier(AXID.Screen.element) on leaf interactive elements only —
/// never on containers with Liquid Glass material (.glassEffect, .background(.regularMaterial), etc.).
public enum AXID {
    public enum Home {
        public static let quickStartButton = "home.quickStartButton"
        /// "Entrenamiento libre": starts a session without a routine (#137 S5).
        public static let freeSessionButton = "home.freeSessionButton"
        public static let nextSessionTitle = "home.nextSessionTitle"
        public static let settingsButton = "home.settingsButton"
        /// "Ver todas" in "Otras rutinas": opens the routine list (T10).
        public static let seeAllRoutinesButton = "home.seeAllRoutinesButton"
        /// Opens the exercises screen (#137 T2b).
        public static let exercisesButton = "home.exercisesButton"

        /// A row of "Otras rutinas" (T10).
        public static func otherRoutine(_ routineId: UUID) -> String {
            "home.otherRoutine.\(routineId.uuidString)"
        }
    }

    /// Routine list (`SessionListView`).
    public enum RoutineList {
        /// Swipe action that marks or unmarks the row's routine as a favourite.
        public static let favoriteAction = "routineList.favoriteAction"

        public static func row(_ routineId: UUID) -> String {
            "routineList.row.\(routineId.uuidString)"
        }
    }

    /// Exercises screen (`ExerciseListView`, #137 T2b).
    public enum Exercises {
        public static func row(_ exerciseId: UUID) -> String {
            "exercises.row.\(exerciseId.uuidString)"
        }
    }

    /// Exercise sheet (`ExerciseSheetView`, #137 S7).
    public enum ExerciseSheet {
        public static let closeButton = "exerciseSheet.closeButton"
        public static let name = "exerciseSheet.name"
        public static let equipment = "exerciseSheet.equipment"
        public static let video = "exerciseSheet.video"
        public static let image = "exerciseSheet.image"
        public static let placeholder = "exerciseSheet.placeholder"
        public static let loading = "exerciseSheet.loading"
        public static let videoNotice = "exerciseSheet.videoNotice"
        public static let primaryMuscles = "exerciseSheet.primaryMuscles"
        public static let secondaryMuscles = "exerciseSheet.secondaryMuscles"

        /// The `number`th setup step, from 1.
        public static func setupStep(_ number: Int) -> String {
            "exerciseSheet.setupStep.\(number)"
        }

        /// The `number`th execution step, from 1.
        public static func executionStep(_ number: Int) -> String {
            "exerciseSheet.executionStep.\(number)"
        }
    }

    /// Routine detail (`SessionDetailView`).
    public enum RoutineDetail {
        public static let favoriteButton = "routineDetail.favoriteButton"
        public static let startButton = "routineDetail.startButton"
    }

    public enum ActiveWorkout {
        public static let elapsedTimer = "activeWorkout.elapsedTimer"
        public static let endButton = "activeWorkout.endButton"
        public static let logSetButton = "activeWorkout.logSetButton"
        /// "Añadir ejercicio": opens the exercise list to pick one (#137 S5).
        public static let addExerciseButton = "activeWorkout.addExerciseButton"
        public static let exercisePickerCancelButton = "activeWorkout.exercisePickerCancelButton"
        public static let exerciseTitle = "activeWorkout.exerciseTitle"
        public static let progressIndicator = "activeWorkout.progressIndicator"
        public static let setWarmupToggle = "activeWorkout.setWarmupToggle"
        public static let exerciseOptionsMenu = "activeWorkout.exerciseOptionsMenu"
        public static let exerciseRestButton = "activeWorkout.exerciseRestButton"
    }

    /// "No has registrado ninguna serie" prompt when ending a workout (T6).
    public enum DiscardWorkout {
        public static let discardButton = "discardWorkout.discardButton"
        public static let keepTrainingButton = "discardWorkout.keepTrainingButton"
    }

    /// "Descanso entre series" sheet of the current exercise.
    public enum ExerciseRest {
        public static let enabledToggle = "exerciseRest.enabledToggle"
        public static let durationLabel = "exerciseRest.durationLabel"
        public static let decreaseButton = "exerciseRest.decreaseButton"
        public static let increaseButton = "exerciseRest.increaseButton"
        public static let doneButton = "exerciseRest.doneButton"
    }

    public enum Settings {
        public static let rirMaximumStepper = "settings.rirMaximumStepper"
        public static let changeExerciseRestToggle = "settings.changeExerciseRestToggle"
        public static let changeExerciseRestDurationLabel = "settings.changeExerciseRestDurationLabel"
        public static let changeExerciseRestDecreaseButton = "settings.changeExerciseRestDecreaseButton"
        public static let changeExerciseRestIncreaseButton = "settings.changeExerciseRestIncreaseButton"
        public static let signOutButton = "settings.signOutButton"
        public static let signOutConfirmButton = "settings.signOutConfirmButton"
        public static let signOutCancelButton = "settings.signOutCancelButton"
    }

    public enum Login {
        public static let screen = "login.screen"
    }

    public enum SetLog {
        public static let repsField = "setLog.repsField"
        public static let weightField = "setLog.weightField"
        public static let saveButton = "setLog.saveButton"
        public static let cancelButton = "setLog.cancelButton"
        public static let warmupToggle = "setLog.warmupToggle"
    }

    public enum RestTimer {
        public static let timerLabel = "restTimer.timerLabel"
        public static let skipButton = "restTimer.skipButton"
        public static let decreaseButton = "restTimer.decreaseButton"
        public static let increaseButton = "restTimer.increaseButton"
    }

    public enum Summary {
        public static let workoutNameLabel = "summary.workoutNameLabel"
        public static let closeButton = "summary.closeButton"
    }
}
