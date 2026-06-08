import SwiftData
import SwiftUI
import TNWTrackerKit

// MARK: - WorkoutHistoryListView

/// Histórico de sesiones completadas (Workout con status `.completed`).
/// Paginado, buscable por nombre. Cada fila navega al detalle editable y ofrece
/// borrado vía swipe con confirmación (patrón recomendado por Apple para
/// acciones destructivas).
struct WorkoutHistoryListView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var model: WorkoutHistoryModel
    @State private var pendingDelete: Workout?

    init(container: ModelContainer) {
        _model = State(initialValue: WorkoutHistoryModel(container: container))
    }

    var body: some View {
        Group {
            if model.isLoading && model.workouts.isEmpty {
                LoadingState(message: "workout-history.loading")
            } else if model.workouts.isEmpty {
                EmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "workout-history.empty-title",
                    message: "workout-history.empty-message"
                )
            } else {
                historyList
            }
        }
        .navigationTitle(Text("workout-history.title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $model.searchQuery, prompt: Text("workout-history.search-placeholder"))
        .task(id: model.searchQuery) {
            await model.loadFirstPage()
        }
        .confirmationDialog(
            Text("workout-history.delete.confirm-title"),
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { workout in
            Button(role: .destructive) {
                delete(workout)
            } label: {
                Text("workout-history.delete.confirm-action")
            }
            Button(role: .cancel) {
                pendingDelete = nil
            } label: {
                Text("workout-history.delete.cancel-action")
            }
        } message: { workout in
            Text(verbatim: String(
                format: String(localized: "workout-history.delete.confirm-message"),
                workout.name
            ))
        }
    }

    // MARK: - List

    private var historyList: some View {
        List {
            ForEach(model.workouts) { workout in
                workoutRow(workout)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = workout
                        } label: {
                            Label("workout-history.delete.action", systemImage: "trash")
                        }
                    }
            }

            if model.hasNextPage {
                loadMoreRow
            }
        }
        .listStyle(.plain)
    }

    private func workoutRow(_ workout: Workout) -> some View {
        Button {
            appEnv.router.push(.workoutDetail(workoutID: workout.id))
        } label: {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(verbatim: workout.name)
                        .font(.headline)

                    HStack(spacing: Spacing.md) {
                        Label {
                            Text(workout.startedAt, format: .dateTime.day().month().year())
                        } icon: {
                            Image(systemName: "calendar")
                        }

                        if let seconds = workout.durationSeconds, seconds > 0 {
                            Label {
                                durationText(seconds: seconds)
                            } icon: {
                                Image(systemName: "clock")
                            }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func durationText(seconds: Int) -> some View {
        let duration = Duration.seconds(seconds)
        if seconds >= 3600 {
            Text(duration, format: .time(pattern: .hourMinuteSecond))
        } else {
            Text(duration, format: .time(pattern: .minuteSecond))
        }
    }

    private var loadMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, Spacing.sm)
            Spacer()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .task {
            await model.loadMore()
        }
    }

    // MARK: - Actions

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private func delete(_ workout: Workout) {
        Task {
            try? await appEnv.workoutRepository.delete(workout)
            pendingDelete = nil
            await model.loadFirstPage()
        }
    }
}

// MARK: - Preview

#Preview("WorkoutHistoryListView — con datos") {
    let container = ModelContainerFactory.previewContainer()
    let context = ModelContext(container)
    let userId = UUID()
    for (i, name) in ["Push Day", "Pull Day", "Legs Day"].enumerated() {
        let w = Workout(userId: userId, name: name)
        w.status = .completed
        w.startedAt = Date().addingTimeInterval(Double(-i) * 86400)
        w.completedAt = w.startedAt
        w.durationSeconds = 3600 + i * 300
        context.insert(w)
    }
    try? context.save()

    return NavigationStack {
        WorkoutHistoryListView(container: container)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}

#Preview("WorkoutHistoryListView — vacío") {
    let container = ModelContainerFactory.previewContainer()
    return NavigationStack {
        WorkoutHistoryListView(container: container)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}
