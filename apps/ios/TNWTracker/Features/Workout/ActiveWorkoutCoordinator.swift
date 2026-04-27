import Foundation
import Observation
import Supabase
import SwiftData
import TNWTrackerKit

/// FSM del workout activo. Coordina sets, timer y Live Activity.
@MainActor
@Observable
public final class ActiveWorkoutCoordinator {
    // MARK: - Phase

    public enum Phase: Sendable, Equatable {
        case idle
        case active
        case restingBetweenSets
        case restingBetweenExercises
        case paused
        case finishing
    }

    // MARK: - Observed state

    public private(set) var workout: Workout?
    public private(set) var workoutExercises: [WorkoutExercise] = []
    public private(set) var currentExerciseIndex: Int = 0
    public private(set) var phase: Phase = .idle
    public private(set) var elapsedSeconds: Int = 0

    // targetSets mapeados desde la Session template
    private var targetSetsMap: [UUID: Int] = [:]
    private var restSecondsMap: [UUID: Int] = [:]

    // MARK: - Dependencies

    private let workoutRepository: WorkoutRepository
    private let syncEngine: SyncEngineImpl
    private let timerService: RestTimerService
    private let liveActivity: LiveActivityController
    private let supabase: SupabaseClient
    private let modelContext: ModelContext
    private let userId: UUID

    private var elapsedTask: Task<Void, Never>?
    private var undoLastSetId: UUID?
    private var undoTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        userId: UUID,
        workoutRepository: WorkoutRepository,
        syncEngine: SyncEngineImpl,
        timerService: RestTimerService,
        liveActivity: LiveActivityController,
        supabase: SupabaseClient,
        modelContext: ModelContext
    ) {
        self.userId = userId
        self.workoutRepository = workoutRepository
        self.syncEngine = syncEngine
        self.timerService = timerService
        self.liveActivity = liveActivity
        self.supabase = supabase
        self.modelContext = modelContext
    }

    // MARK: - Lifecycle

    /// Inicia el workout desde una Session template.
    public func start(from session: Session) async throws {
        guard phase == .idle else { return }
        let existing = try await workoutRepository.fetchActive()
        guard existing == nil else { return }

        let w = Workout(userId: userId, name: session.name)
        w.sessionId = session.id
        modelContext.insert(w)

        let sorted = session.sessionExercises.sorted { $0.orderIndex < $1.orderIndex }
        for (idx, se) in sorted.enumerated() {
            let we = WorkoutExercise(workoutId: w.id, exerciseId: se.exerciseId, orderIndex: idx)
            modelContext.insert(we)
            w.workoutExercises.append(we)
            if let ts = se.targetSets { targetSetsMap[we.id] = ts }
            if let rs = se.restBetweenSetsSeconds { restSecondsMap[we.id] = rs }
        }

        try modelContext.save()
        try await workoutRepository.create(w)

        workout = w
        workoutExercises = w.workoutExercises.sorted { $0.orderIndex < $1.orderIndex }
        currentExerciseIndex = 0
        phase = .active
        liveActivity.start(workoutId: w.id, workoutName: w.name)
        startElapsedTimer()
    }

    /// Inicia un workout ad-hoc sin Session template.
    public func startAdHoc(name: String) async throws {
        guard phase == .idle else { return }
        let existing = try await workoutRepository.fetchActive()
        guard existing == nil else { return }

        let w = Workout(userId: userId, name: name)
        modelContext.insert(w)
        try modelContext.save()
        try await workoutRepository.create(w)

        workout = w
        workoutExercises = []
        currentExerciseIndex = 0
        phase = .active
        liveActivity.start(workoutId: w.id, workoutName: w.name)
        startElapsedTimer()
    }

    // MARK: - Set logging

    /// Registra una serie y evalúa transición de fase según timerTriggerMode.
    public func recordSet(
        reps: Int,
        weight: Double?,
        weightUnit: WeightUnit,
        rpe: Int?,
        isWarmup: Bool,
        timerTriggerMode: TimerTriggerMode
    ) async throws {
        guard let w = workout, let we = currentExercise else { return }

        let setNumber = we.exerciseSets.count + 1
        let set = ExerciseSet(workoutExerciseId: we.id, setNumber: setNumber)
        set.reps = reps
        set.weight = weight
        set.weightUnit = weightUnit
        set.rpe = rpe
        set.isWarmup = isWarmup
        set.completedAt = Date()
        modelContext.insert(set)
        we.exerciseSets.append(set)
        try modelContext.save()

        try await syncEngine.enqueueLocalChange(
            tableName: "exercise_sets",
            recordId: set.id,
            operationType: "insert",
            payload: nil
        )

        // Ventana de undo de 5s
        undoLastSetId = set.id
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.undoLastSetId = nil
        }

        guard timerTriggerMode == .auto, !isWarmup else { return }

        let target = targetSetsMap[we.id] ?? Int.max
        let restSeconds = restSecondsMap[we.id] ?? 90
        let isLastSet = setNumber >= target
        let isLastExercise = currentExerciseIndex >= workoutExercises.count - 1

        if isLastSet && isLastExercise {
            phase = .finishing
        } else if isLastSet {
            phase = .restingBetweenExercises
            await timerService.start(workoutId: w.id, type: .betweenExercises, durationSeconds: restSeconds)
        } else {
            phase = .restingBetweenSets
            await timerService.start(workoutId: w.id, type: .betweenSets, durationSeconds: restSeconds)
        }
    }

    /// Deshace la última serie si todavía está en la ventana de undo.
    public func undoLastSet() async throws {
        guard let setId = undoLastSetId else { return }
        undoTask?.cancel()
        undoLastSetId = nil

        let descriptor = FetchDescriptor<ExerciseSet>(
            predicate: #Predicate { $0.id == setId }
        )
        if let set = try? modelContext.fetch(descriptor).first {
            modelContext.delete(set)
            try? modelContext.save()
        }

        await timerService.skip()
        if phase == .restingBetweenSets || phase == .restingBetweenExercises {
            phase = .active
        }
    }

    // MARK: - Navigation

    public func advanceToNextExercise() {
        guard currentExerciseIndex < workoutExercises.count - 1 else { return }
        currentExerciseIndex += 1
        phase = .active
    }

    public func skipTimer() async {
        let wasRestingBetweenExercises = (phase == .restingBetweenExercises)
        await timerService.skip()
        phase = .active
        if wasRestingBetweenExercises {
            advanceToNextExercise()
        }
    }

    // MARK: - Pause / Resume

    public func pause() async throws {
        guard let w = workout, phase == .active else { return }
        w.statusRaw = WorkoutStatus.paused.rawValue
        try modelContext.save()
        try await workoutRepository.update(w)
        elapsedTask?.cancel()
        phase = .paused
    }

    public func resume() async throws {
        guard let w = workout, phase == .paused else { return }
        w.statusRaw = WorkoutStatus.active.rawValue
        try modelContext.save()
        try await workoutRepository.update(w)
        phase = .active
        startElapsedTimer()
    }

    // MARK: - Finish

    public func finish() async throws {
        guard let w = workout else { return }
        elapsedTask?.cancel()
        await timerService.skip()

        w.durationSeconds = elapsedSeconds
        try await workoutRepository.complete(w)
        try await syncEngine.pushPendingChanges()

        // Invocar Edge Function para calcular PRs
        try? await supabase.functions.invoke(
            "calc_personal_records",
            options: .init(body: ["workout_id": w.id.uuidString])
        )

        await liveActivity.end()

        workout = nil
        workoutExercises = []
        targetSetsMap = [:]
        restSecondsMap = [:]
        currentExerciseIndex = 0
        phase = .idle
        elapsedSeconds = 0
    }

    // MARK: - Helpers

    public var currentExercise: WorkoutExercise? {
        guard workoutExercises.indices.contains(currentExerciseIndex) else { return nil }
        return workoutExercises[currentExerciseIndex]
    }

    private func startElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                elapsedSeconds += 1
            }
        }
    }
}

// MARK: - TimerTriggerMode

public enum TimerTriggerMode: String, Codable, Sendable {
    case auto
    case manual
}
