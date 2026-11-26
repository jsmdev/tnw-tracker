import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseSheetHost

/// The app's exercise sheet (AC1-AC5): loads the exercise of `exerciseID` from
/// the account's store and shows its sheet with the actions to train it or add
/// it to a routine. `RootView` presents it from `Router.presentedExercise`.
struct ExerciseSheetHost: View {
    let exerciseID: UUID
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.relatedLinksUseNetwork) private var useNetwork
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let exercise = (try? appEnv.exerciseRepository.exercise(id: exerciseID)) ?? nil {
            ExerciseSheetView(
                content: ExerciseSheetContent(exercise),
                library: appEnv.exerciseMedia,
                links: appEnv.exerciseLinkRepository,
                // UI tests never fetch a preview: the stand-in answers instead.
                previews: useNetwork ? LiveLinkPreviewProvider() : StandInLinkPreviewProvider(),
                actions: ExerciseSheetActions(
                    routines: appEnv.routineRepository,
                    hasSessionInProgress: ((try? appEnv.sessionRepository.activeSession()) ?? nil) != nil,
                    train: { appEnv.router.train(exerciseID) }
                )
            )
        } else {
            NavigationStack {
                EmptyState(
                    systemImage: "dumbbell",
                    title: "exercise-sheet.not-found-title",
                    message: "exercise-sheet.not-found-message"
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .close) { dismiss() }
                            .accessibilityIdentifier(AXID.ExerciseSheet.closeButton)
                    }
                }
            }
        }
    }
}
