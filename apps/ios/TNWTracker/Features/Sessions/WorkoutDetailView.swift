import SwiftData
import SwiftUI
import TNWTrackerKit

// MARK: - WorkoutDetailView

/// Detalle de una sesión completada del histórico. Modo lectura por defecto;
/// "Editar" habilita la modificación de metadatos (nombre, fecha, notas) y de
/// las series (reps, peso, RPE, calentamiento). Guardar persiste vía
/// `WorkoutRepository` (encola sync); Cancelar revierte con `rollback()`.
///
/// Carga sobre el `@Environment(\.modelContext)` (mainContext) — el mismo que
/// usa el repositorio — para que `update`/`updateSet` persistan los objetos.
struct WorkoutDetailView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.modelContext) private var modelContext

    let workoutID: UUID

    @State private var workout: Workout?
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var isEditing = false
    @State private var isLoading = true
    @State private var isSaving = false

    var body: some View {
        Group {
            if isLoading {
                LoadingState(message: "workout-detail.loading")
            } else if let workout {
                content(workout: workout)
            } else {
                EmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "workout-detail.not-found-title",
                    message: "workout-detail.not-found-message"
                )
            }
        }
        .navigationTitle(Text("workout-detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editToolbar }
        .task { await load() }
    }

    // MARK: - Content

    private func content(workout: Workout) -> some View {
        Form {
            metadataSection(workout: workout)
            ForEach(sortedExercises(workout)) { we in
                exerciseSection(we)
            }
        }
        .disabled(isSaving)
    }

    private func metadataSection(workout: Workout) -> some View {
        Section(header: Text("workout-detail.metadata-section")) {
            // Nombre
            if isEditing {
                TextField("workout-detail.name-field", text: bind(\.name, on: workout))
            } else {
                LabeledContent("workout-detail.name-field") {
                    Text(verbatim: workout.name)
                }
            }

            // Fecha
            if isEditing {
                DatePicker(
                    "workout-detail.date-field",
                    selection: bind(\.startedAt, on: workout),
                    displayedComponents: [.date, .hourAndMinute]
                )
            } else {
                LabeledContent("workout-detail.date-field") {
                    Text(workout.startedAt, format: .dateTime.day().month().year().hour().minute())
                }
            }

            // Notas
            if isEditing {
                TextField(
                    "workout-detail.notes-field",
                    text: bindOptionalString(\.notes, on: workout),
                    axis: .vertical
                )
                .lineLimit(1 ... 4)
            } else if let notes = workout.notes, !notes.isEmpty {
                LabeledContent("workout-detail.notes-field") {
                    Text(verbatim: notes)
                }
            }
        }
    }

    private func exerciseSection(_ we: WorkoutExercise) -> some View {
        Section(header: Text(verbatim: exerciseNames[we.exerciseId] ?? we.exerciseId.uuidString)) {
            let sets = we.exerciseSets.sorted { $0.setNumber < $1.setNumber }
            if sets.isEmpty {
                Text("workout-detail.no-sets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sets) { set in
                    SetEditRow(set: set, isEditing: isEditing)
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        if workout != nil {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        cancelEditing()
                    } label: {
                        Text("workout-detail.cancel-button")
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Text("workout-detail.save-button")
                    }
                    .disabled(isSaving)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEditing = true
                    } label: {
                        Text("workout-detail.edit-button")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sortedExercises(_ workout: Workout) -> [WorkoutExercise] {
        workout.workoutExercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Binding directo a una propiedad no opcional del modelo (SwiftData lo hace
    /// observable; la mutación queda en el contexto hasta save/rollback).
    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<Workout, T>, on workout: Workout) -> Binding<T> {
        Binding(get: { workout[keyPath: keyPath] }, set: { workout[keyPath: keyPath] = $0 })
    }

    private func bindOptionalString(
        _ keyPath: ReferenceWritableKeyPath<Workout, String?>,
        on workout: Workout
    ) -> Binding<String> {
        Binding(
            get: { workout[keyPath: keyPath] ?? "" },
            set: { workout[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    // MARK: - Actions

    private func cancelEditing() {
        // Revierte todos los cambios en memoria que no se guardaron.
        modelContext.rollback()
        isEditing = false
    }

    private func save() async {
        guard let workout else { return }
        isSaving = true
        defer { isSaving = false }

        // SwiftData ya sabe qué se modificó: sincronizamos SOLO eso, sin reenviar
        // series intactas. Capturamos el snapshot ANTES de cualquier save, porque
        // update*/updateSet vuelven a marcar los objetos como cambiados.
        let changed = modelContext.changedModelsArray
        let setIDs = Set(workout.workoutExercises.flatMap { $0.exerciseSets.map(\.id) })
        let changedSets = changed.compactMap { $0 as? ExerciseSet }.filter { setIDs.contains($0.id) }
        let metadataChanged = changed.contains { ($0 as? Workout)?.id == workout.id }

        do {
            if metadataChanged {
                try await appEnv.workoutRepository.updateMetadata(workout)
            }
            for set in changedSets {
                try await appEnv.workoutRepository.updateSet(set)
            }

            // Si cambiaron series, empujamos el cambio y pedimos al backend que
            // recalcule los récords personales (best-effort, no bloquea la UI).
            if !changedSets.isEmpty {
                try? await appEnv.syncEngine.pushPendingChanges()
                await appEnv.recalculatePersonalRecords(for: workout.id)
            }

            isEditing = false
        } catch {
            // Ante error, mantenemos el modo edición para que el usuario reintente.
        }
    }

    // MARK: - Data Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        var descriptor = FetchDescriptor<Workout>()
        descriptor.predicate = #Predicate<Workout> { $0.id == workoutID }
        descriptor.fetchLimit = 1
        guard let fetched = try? modelContext.fetch(descriptor).first else {
            workout = nil
            return
        }
        workout = fetched

        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        exerciseNames = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
    }
}

// MARK: - SetEditRow

/// Fila de una serie. En modo lectura muestra reps × peso (+ RPE/calentamiento);
/// en modo edición expone los controles. Edita el `ExerciseSet` directamente —
/// los cambios viven en el contexto hasta que el padre guarda o revierte.
private struct SetEditRow: View {
    @Bindable var set: ExerciseSet
    let isEditing: Bool

    var body: some View {
        if isEditing {
            editing
        } else {
            reading
        }
    }

    // MARK: - Reading

    private var reading: some View {
        HStack(spacing: Spacing.md) {
            Text(verbatim: setNumberLabel)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            if set.isWarmup {
                Image(systemName: "flame")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("workout-detail.warmup-label")
            }

            Text(verbatim: readingSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var readingSummary: String {
        let reps = set.reps.map(String.init) ?? "—"
        let weight = set.weight.map { String(format: "%g", $0) } ?? "—"
        var parts = "\(reps) × \(weight) \(set.weightUnitRaw)"
        if let rpe = set.rpe {
            parts += "  ·  RPE \(rpe)"
        }
        return parts
    }

    // MARK: - Editing

    private var editing: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(verbatim: setNumberLabel)
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: Spacing.md) {
                LabeledField(titleKey: "workout-detail.reps-field") {
                    TextField("workout-detail.reps-field", text: repsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledField(titleKey: "workout-detail.weight-field") {
                    TextField("workout-detail.weight-field", text: weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Picker("workout-detail.rpe-field", selection: rpeSelection) {
                Text("workout-detail.rpe-none").tag(0)
                ForEach(1 ... 10, id: \.self) { value in
                    Text(verbatim: "\(value)").tag(value)
                }
            }

            Toggle("workout-detail.warmup-field", isOn: $set.isWarmup)
        }
        .padding(.vertical, Spacing.xs)
    }

    /// Etiqueta "Serie N" resuelta con `String(localized:)` + format para evitar
    /// generar una `LocalizedStringKey` con el placeholder embebido en la clave.
    private var setNumberLabel: String {
        String(format: String(localized: "workout-detail.set-number"), set.setNumber)
    }

    // MARK: - Bindings

    private var repsText: Binding<String> {
        Binding(
            get: { set.reps.map(String.init) ?? "" },
            set: { set.reps = Int($0.filter(\.isNumber)) }
        )
    }

    private var weightText: Binding<String> {
        Binding(
            get: { set.weight.map { String(format: "%g", $0) } ?? "" },
            set: { set.weight = Double($0.replacingOccurrences(of: ",", with: ".")) }
        )
    }

    /// 0 representa "sin RPE"; 1...10 el valor (respeta el CHECK del backend).
    private var rpeSelection: Binding<Int> {
        Binding(
            get: { set.rpe ?? 0 },
            set: { set.rpe = $0 == 0 ? nil : $0 }
        )
    }
}

// MARK: - LabeledField

/// Pequeño contenedor etiqueta + control para las filas de edición de series.
private struct LabeledField<Content: View>: View {
    let titleKey: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview("WorkoutDetailView") {
    let container = ModelContainerFactory.previewContainer()
    let context = ModelContext(container)
    let userId = UUID()
    let exerciseId = UUID()

    let exercise = Exercise(name: "Bench Press", category: "strength")
    exercise.id = exerciseId
    context.insert(exercise)

    let workout = Workout(userId: userId, name: "Push Day")
    workout.status = .completed
    workout.completedAt = Date()
    workout.durationSeconds = 3720
    context.insert(workout)

    let we = WorkoutExercise(workoutId: workout.id, exerciseId: exerciseId, orderIndex: 0)
    context.insert(we)
    workout.workoutExercises.append(we)
    for i in 1 ... 3 {
        let s = ExerciseSet(workoutExerciseId: we.id, setNumber: i)
        s.reps = 8; s.weight = 80; s.rpe = 8
        context.insert(s); we.exerciseSets.append(s)
    }
    try? context.save()

    return NavigationStack {
        WorkoutDetailView(workoutID: workout.id)
    }
    .environment(AppEnvironment.bootstrap(modelContext: container.mainContext))
    .modelContainer(container)
}
