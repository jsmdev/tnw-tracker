import SwiftUI
import TNWTrackerKit

// MARK: - ExerciseSheetActions

/// What the exercise sheet can do with its exercise (AC3-AC5). Absent in
/// previews; the sheet then shows no buttons.
struct ExerciseSheetActions {
    let routines: any RoutineRepositoryProtocol
    /// A workout is in progress: training adds the exercise to it.
    let hasSessionInProgress: Bool
    /// «Entrenar este ejercicio» / «Añadir a la sesión en curso».
    let train: () -> Void
}

// MARK: - ExerciseSheetActionsSection

/// «Entrenar este ejercicio» (or «Añadir a la sesión en curso» while a workout
/// is in progress) and «Añadir a rutina», which offers the user's routines and
/// «Nueva rutina…», which asks only for the name.
struct ExerciseSheetActionsSection: View {
    let actions: ExerciseSheetActions
    @State private var model: AddToRoutineModel
    @State private var asksNewRoutineName = false
    @State private var newRoutineName = ""
    @State private var message: Message?

    init(exerciseId: UUID, actions: ExerciseSheetActions) {
        self.actions = actions
        _model = State(initialValue: AddToRoutineModel(exerciseId: exerciseId, routines: actions.routines))
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            PrimaryButton(
                title: actions.hasSessionInProgress ? "exercise-sheet.add-to-session" : "exercise-sheet.train",
                action: actions.train
            )
            .accessibilityIdentifier(AXID.ExerciseSheet.trainButton)

            addToRoutineButton
        }
        .onAppear { model.load() }
        .alert("exercise-sheet.new-routine.title", isPresented: $asksNewRoutineName) {
            TextField("exercise-sheet.new-routine.name", text: $newRoutineName)
            Button("exercise-sheet.new-routine.create") { createRoutine() }
                .disabled(!AddToRoutineModel.isValidName(newRoutineName))
                .accessibilityIdentifier(AXID.ExerciseSheet.newRoutineCreate)
            Button("exercise-sheet.new-routine.cancel", role: .cancel) {}
        } message: {
            Text("exercise-sheet.new-routine.message")
        }
        .alert(message?.title ?? Text(verbatim: ""), isPresented: isShowingMessage) {
            Button("exercise-sheet.message.ok") {}
                .accessibilityIdentifier(AXID.ExerciseSheet.addToRoutineResult)
        }
    }

    /// A menu with a plain label, as «Añadir enlace» in the same sheet: with a
    /// bordered or glass label the contrast audit times out once it scrolls
    /// under the bar.
    private var addToRoutineButton: some View {
        Menu {
            Section {
                ForEach(model.routines) { routine in
                    Button {
                        add(to: routine)
                    } label: {
                        Text(verbatim: routine.name)
                    }
                }
            }
            Button {
                newRoutineName = ""
                asksNewRoutineName = true
            } label: {
                Label("exercise-sheet.new-routine.button", systemImage: "plus")
            }
        } label: {
            Label("exercise-sheet.add-to-routine", systemImage: "text.badge.plus")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(AXID.ExerciseSheet.addToRoutineButton)
    }

    private var isShowingMessage: Binding<Bool> {
        Binding { message != nil } set: { shown in
            if !shown {
                message = nil
            }
        }
    }

    private func add(to routine: Routine) {
        do {
            switch try model.add(to: routine.id) {
            case let .added(name):
                message = Message(title: Text("exercise-sheet.added-to-routine \(name)"))
            case let .alreadyInRoutine(name):
                message = Message(title: Text("exercise-sheet.already-in-routine \(name)"))
            }
        } catch {
            model.load()
            message = Message(title: Text("exercise-sheet.add-to-routine-failed"))
        }
    }

    private func createRoutine() {
        do {
            let routine = try model.createRoutine(named: newRoutineName)
            message = Message(title: Text("exercise-sheet.added-to-routine \(routine.name)"))
        } catch {
            message = Message(title: Text("exercise-sheet.add-to-routine-failed"))
        }
    }

    /// The alert after adding, with the routine's name.
    private struct Message: Identifiable {
        let id = UUID()
        let title: Text
    }
}
