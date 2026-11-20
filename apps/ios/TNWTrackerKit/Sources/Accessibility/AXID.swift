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
        public static let nextSessionTitle = "home.nextSessionTitle"
        public static let settingsButton = "home.settingsButton"
        /// "Ver todas" in "Otras rutinas": opens the routine list (T10).
        public static let seeAllRoutinesButton = "home.seeAllRoutinesButton"

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

    /// Routine detail (`SessionDetailView`).
    public enum RoutineDetail {
        public static let favoriteButton = "routineDetail.favoriteButton"
        public static let startButton = "routineDetail.startButton"
    }

    public enum ActiveWorkout {
        public static let elapsedTimer = "activeWorkout.elapsedTimer"
        public static let endButton = "activeWorkout.endButton"
        public static let logSetButton = "activeWorkout.logSetButton"
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
        public static let syncStatusMessage = "settings.syncStatusMessage"
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
