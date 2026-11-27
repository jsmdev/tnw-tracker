import SwiftUI
import TNWTrackerKit

// MARK: - WorkoutDetailView

/// A finished workout of the history: when it was, how long it took, and
/// every set of each exercise. A workout without machine data can be deleted (#174 S7).
/// Tapping an exercise opens its sheet (AC1).
struct WorkoutDetailView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @State private var model: WorkoutDetailModel
    @State private var confirmsDelete = false
    @State private var deleteFailed = false

    init(
        sessionID: UUID,
        sessions: any SessionRepositoryProtocol,
        exercises: any ExerciseRepositoryProtocol
    ) {
        _model = State(initialValue: WorkoutDetailModel(sessionID: sessionID, sessions: sessions, exercises: exercises))
    }

    var body: some View {
        Group {
            if let session = model.session {
                content(session)
            } else if model.isLoaded {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "history.detail.not-found-title",
                    message: "history.detail.not-found-message"
                )
            } else {
                // Never an empty Group: its modifiers, `onAppear` included, would apply to nothing.
                ProgressView()
            }
        }
        .navigationTitle(model.session.map(Self.title) ?? Text(verbatim: ""))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if model.canDelete {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmsDelete = true
                    } label: {
                        Label("history.delete.button", systemImage: "trash")
                    }
                    .accessibilityIdentifier(AXID.WorkoutDetail.deleteButton)
                }
            }
        }
        .deleteWorkoutAlert(isPresented: $confirmsDelete) {
            do {
                try model.delete()
                dismiss()
            } catch {
                deleteFailed = true
            }
        }
        .deleteWorkoutFailedAlert(isPresented: $deleteFailed)
        .onAppear { model.load() }
    }

    static func title(_ session: TrainingSession) -> Text {
        session.name.map { Text(verbatim: $0) } ?? Text("free-session.name")
    }

    private func content(_ session: TrainingSession) -> some View {
        List {
            summary(session)
            ForEach(model.sections) { section in
                Section {
                    // A row, not a section header: the system header fails the Dynamic Type audit.
                    Button {
                        appEnv.router.presentExercise(section.exerciseId)
                    } label: {
                        HStack {
                            Group {
                                if let name = section.exerciseName {
                                    Text(verbatim: name)
                                } else {
                                    Text("history.detail.unknown-exercise")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint(Text("history.detail.exercise-hint"))
                    .accessibilityIdentifier(AXID.WorkoutDetail.exercise(section.id))
                    ForEach(section.sets) { shown in
                        WorkoutSetRow(shown: shown)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(AXID.WorkoutDetail.list)
    }

    private func summary(_ session: TrainingSession) -> some View {
        Section {
            summaryRows(session)
        } footer: {
            if session.hasImportedData {
                Text("history.detail.imported-note")
                    .accessibilityIdentifier(AXID.WorkoutDetail.importedNote)
            }
        }
    }

    @ViewBuilder
    private func summaryRows(_ session: TrainingSession) -> some View {
        if let completedAt = session.completedAt {
            LabeledContent("history.detail.date") {
                Text(completedAt, format: .dateTime.weekday(.wide).day().month(.wide).year())
            }
        }
        if let startedAt = session.startedAt {
            LabeledContent("history.detail.started-at") {
                Text(startedAt, format: .dateTime.hour().minute())
            }
        }
        if let seconds = session.durationSeconds {
            LabeledContent("history.detail.duration") {
                Text(Duration.seconds(seconds), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
            }
        }
        LabeledContent("history.detail.exercises") {
            Text(verbatim: "\(model.sections.count)")
        }
        if session.volumeKg > 0 {
            LabeledContent("history.detail.volume") {
                Text("history.row.volume \(session.volumeKg.formatted(.number.precision(.fractionLength(0))))")
            }
        }
    }
}

// MARK: - WorkoutSetRow

/// One set: its number (or the warm-up mark) and its values.
private struct WorkoutSetRow: View {
    let shown: WorkoutDetailModel.ShownSet

    var body: some View {
        HStack(spacing: Spacing.md) {
            Group {
                if let number = shown.number {
                    Text(verbatim: "\(number)")
                } else {
                    Text("set.warmup-short")
                }
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(minWidth: 28)

            values
            Spacer()
            if shown.value.source == .imported {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("history.detail.machine-set"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var values: some View {
        let values = shown.value.values
        return HStack(spacing: Spacing.xs) {
            if let reps = values.reps {
                Text("set.reps \(reps)")
            }
            if let weight = values.weight {
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text("history.detail.weight \(weight.kilograms.formatted(.number))")
            }
            if let seconds = values.durationSeconds {
                Text(
                    Duration.seconds(seconds),
                    format: .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)
                )
            }
            if let meters = values.distanceMeters {
                Text(Measurement(value: meters, unit: UnitLength.meters), format: .measurement(width: .abbreviated))
            }
            if let rir = values.rir {
                Text(verbatim: "·").foregroundStyle(.secondary)
                Text("history.detail.rir \(rir)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Delete confirmation

extension View {
    /// "¿Borrar entrenamiento?" with a destructive confirm, shared by the list and the detail.
    func deleteWorkoutAlert(isPresented: Binding<Bool>, onConfirm: @escaping () -> Void) -> some View {
        alert(Text("history.delete.title"), isPresented: isPresented) {
            Button(role: .destructive, action: onConfirm) {
                Text("history.delete.confirm")
            }
            .accessibilityIdentifier(AXID.DeleteWorkout.confirm)
            Button(role: .cancel) {} label: {
                Text("history.delete.cancel")
            }
            .accessibilityIdentifier(AXID.DeleteWorkout.cancel)
        } message: {
            Text("history.delete.message")
        }
    }

    func deleteWorkoutFailedAlert(isPresented: Binding<Bool>) -> some View {
        alert(Text("history.delete.failed"), isPresented: isPresented) {
            Button(role: .cancel) {} label: {
                Text("history.delete.ok")
            }
        }
    }
}
