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
        /// "Continuar entrenamiento": reopens the session left in progress.
        public static let continueButton = "home.continueButton"
        public static let nextSessionTitle = "home.nextSessionTitle"
        public static let settingsButton = "home.settingsButton"
        /// "Ver todas" in "Otras rutinas": opens the routine list (T10).
        public static let seeAllRoutinesButton = "home.seeAllRoutinesButton"

        /// A row of "Otras rutinas" (T10).
        public static func otherRoutine(_ routineId: UUID) -> String {
            "home.otherRoutine.\(routineId.uuidString)"
        }
    }

    /// The tab bar (#174).
    public enum Tabs {
        public static let home = "tabs.home"
        public static let history = "tabs.history"
        public static let exercises = "tabs.exercises"
    }

    /// The Historial tab (#174).
    public enum History {
        public static let list = "history.list"

        public static func row(_ sessionId: UUID) -> String {
            "history.row.\(sessionId.uuidString)"
        }

        /// The swipe action that deletes a finished workout (#174 S7).
        public static let deleteAction = "history.deleteAction"
        /// "N sesiones" under the filters (#174 S8).
        public static let count = "history.count"
        public static let clearFilters = "history.clearFilters"
        public static let noResults = "history.noResults"
        /// The title row of a month section.
        public static let month = "history.month"

        public static func kindChip(_ kind: String) -> String {
            "history.kind.\(kind)"
        }

        public static func periodChip(_ period: String) -> String {
            "history.period.\(period)"
        }

        public static func sourceChip(_ source: String) -> String {
            "history.source.\(source)"
        }
    }

    /// A finished workout of the history (#174 S7).
    public enum WorkoutDetail {
        public static let list = "workoutDetail.list"
        public static let deleteButton = "workoutDetail.deleteButton"
        /// Why a workout with machine data has no delete button.
        public static let importedNote = "workoutDetail.importedNote"

        public static func exercise(_ entryId: UUID) -> String {
            "workoutDetail.exercise.\(entryId.uuidString)"
        }
    }

    /// The confirmation shown before deleting a finished workout (#174 S7).
    public enum DeleteWorkout {
        public static let confirm = "deleteWorkout.confirm"
        public static let cancel = "deleteWorkout.cancel"
    }

    /// "Sesión en curso" above the tab bar (#174 S5).
    public enum SessionAccessory {
        public static let button = "sessionAccessory.button"
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

    /// The sheet that adds a personal related link or edits its title (`RelatedLinkFormSheet`, S10).
    public enum RelatedLinkForm {
        public static let address = "relatedLinkForm.address"
        public static let title = "relatedLinkForm.title"
        public static let site = "relatedLinkForm.site"
        public static let previewImage = "relatedLinkForm.previewImage"
        public static let previewLoading = "relatedLinkForm.previewLoading"
        public static let noPreview = "relatedLinkForm.noPreview"
        public static let problem = "relatedLinkForm.problem"
        public static let saveButton = "relatedLinkForm.saveButton"
        public static let cancelButton = "relatedLinkForm.cancelButton"
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
        public static let videoToggle = "exerciseSheet.videoToggle"
        public static let videoLoading = "exerciseSheet.videoLoading"
        public static let primaryMuscles = "exerciseSheet.primaryMuscles"
        public static let secondaryMuscles = "exerciseSheet.secondaryMuscles"
        public static let relatedLinks = "exerciseSheet.relatedLinks"
        /// The «Información relacionada» header.
        public static let relatedHeader = "exerciseSheet.relatedHeader"
        public static let relatedLinkPlayer = "exerciseSheet.relatedLinkPlayer"
        public static let relatedLinkNotice = "exerciseSheet.relatedLinkNotice"
        /// «Añadir enlace», at the end of «Información relacionada» (S10).
        public static let addLinkButton = "exerciseSheet.addLinkButton"
        /// «Editar título» and «Eliminar» in a personal link's menu.
        public static let relatedLinkEditTitle = "exerciseSheet.relatedLinkEditTitle"
        public static let relatedLinkDelete = "exerciseSheet.relatedLinkDelete"
        /// «Eliminar» in the confirmation of a personal link's deletion.
        public static let relatedLinkDeleteConfirm = "exerciseSheet.relatedLinkDeleteConfirm"

        /// The `number`th related link's row, from 1: ours, then the user's.
        public static func relatedLink(_ number: Int) -> String {
            "exerciseSheet.relatedLink.\(number)"
        }

        /// "Abrir en YouTube" under the `number`th related link, from 1.
        public static func relatedLinkOpen(_ number: Int) -> String {
            "exerciseSheet.relatedLinkOpen.\(number)"
        }

        /// The menu of the `number`th related link, from 1; only personal links have one.
        public static func relatedLinkMenu(_ number: Int) -> String {
            "exerciseSheet.relatedLinkMenu.\(number)"
        }

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
        public static let deleteSetButton = "activeWorkout.deleteSetButton"
        public static let removeExerciseButton = "activeWorkout.removeExerciseButton"
        public static let removeExerciseConfirm = "activeWorkout.removeExerciseConfirm"
        /// Closes the workout screen and leaves the session in progress.
        public static let minimizeButton = "activeWorkout.minimizeButton"
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

    public enum Splash {
        public static let screen = "splash.screen"
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
