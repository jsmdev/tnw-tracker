import Foundation
import Observation
import os.log
import Supabase
import SwiftData
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

// MARK: - DrainCoordinatorProtocol

/// Minimal protocol for drain dispatch — testable without the full coordinator.
/// Only the methods and properties called by drainIfActive / drainPendingIntents are declared here.
@MainActor
public protocol DrainCoordinatorProtocol: AnyObject {
    /// The ID of the currently active workout, or nil if no workout is running.
    var activeWorkoutId: UUID? { get }
    func skipTimer() async
    func pause() async throws
    func resume() async throws
    func finish() async throws
}

/// FSM del workout activo. Coordina sets, timer y Live Activity.
/// La decisión pura de transición de fase tras un set vive en
/// `WorkoutPhaseTransition` (Kit) para poder testearla en aislamiento.
@MainActor
@Observable
public final class ActiveWorkoutCoordinator: DrainCoordinatorProtocol {
    // MARK: - Observed state

    public private(set) var workout: Workout?
    public private(set) var workoutExercises: [WorkoutExercise] = []
    public private(set) var currentExerciseIndex: Int = 0
    public private(set) var phase: WorkoutPhase = .idle
    public private(set) var elapsedSeconds: Int = 0
    public var timerTriggerMode: TimerTriggerMode = .auto

    /// Set to the completed workout ID just before state is cleared in `finish()`.
    /// Observers (ActiveWorkoutView) use this to trigger WorkoutSummaryView.
    public private(set) var completedWorkoutId: UUID?

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
    public func start(from session: TNWTrackerKit.Session) async throws {
        guard phase == .idle else { return }
        // Si quedó un workout activo/pausado sin terminar (p.ej. la app se cerró a
        // mitad o un finish() previo falló en red), lo reanudamos en vez de crear uno
        // nuevo o quedar en silencio con phase .idle (bug #88: spinner infinito).
        if let existing = try await workoutRepository.fetchActive() {
            adoptExisting(existing)
            return
        }

        let wkt = Workout(userId: userId, name: session.name)
        wkt.sessionId = session.id
        modelContext.insert(wkt)

        let sorted = session.sessionExercises.sorted { $0.orderIndex < $1.orderIndex }
        for (idx, se) in sorted.enumerated() {
            let we = WorkoutExercise(workoutId: wkt.id, exerciseId: se.exerciseId, orderIndex: idx)
            modelContext.insert(we)
            wkt.workoutExercises.append(we)
            if let ts = se.targetSets { targetSetsMap[we.id] = ts }
            if let rs = se.restBetweenSetsSeconds { restSecondsMap[we.id] = rs }
        }

        try modelContext.save()
        try await workoutRepository.create(wkt)

        workout = wkt
        workoutExercises = wkt.workoutExercises.sorted { $0.orderIndex < $1.orderIndex }
        currentExerciseIndex = 0
        phase = .active
        logger.info("Coordinator phase → .active (start from session: \(session.id))")
        liveActivity.start(workoutId: wkt.id, workoutName: wkt.name)
        startElapsedTimer()
    }

    /// Inicia un workout ad-hoc sin Session template.
    public func startAdHoc(name: String) async throws {
        guard phase == .idle else { return }
        if let existing = try await workoutRepository.fetchActive() {
            adoptExisting(existing)
            return
        }

        let wkt = Workout(userId: userId, name: name)
        modelContext.insert(wkt)
        try modelContext.save()
        try await workoutRepository.create(wkt)

        workout = wkt
        workoutExercises = []
        currentExerciseIndex = 0
        phase = .active
        logger.info("Coordinator phase → .active (ad-hoc: \(name))")
        liveActivity.start(workoutId: wkt.id, workoutName: wkt.name)
        startElapsedTimer()
    }

    // MARK: - Resume residual

    /// Reanuda un workout activo/pausado residual: restaura el estado del
    /// coordinador desde SwiftData en vez de crear uno nuevo. Evita perder datos
    /// y el spinner infinito (bug #88).
    private func adoptExisting(_ existing: Workout) {
        workout = existing
        workoutExercises = existing.workoutExercises.sorted { $0.orderIndex < $1.orderIndex }
        repopulateMaps(for: existing)
        currentExerciseIndex = firstIncompleteExerciseIndex()
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(existing.startedAt)))
        phase = (existing.status == .paused) ? .paused : .active
        liveActivity.start(workoutId: existing.id, workoutName: existing.name)
        if phase == .active { startElapsedTimer() }
        let resumedId = existing.id
        logger.info("Coordinator adoptó workout residual \(resumedId)")
    }

    /// Repuebla targetSetsMap/restSecondsMap desde la Session original del workout,
    /// para que la evaluación de descansos siga funcionando tras reanudar.
    private func repopulateMaps(for wkt: Workout) {
        guard let sessionId = wkt.sessionId else { return }
        var descriptor = FetchDescriptor<TNWTrackerKit.Session>(
            predicate: #Predicate { $0.id == sessionId }
        )
        descriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(descriptor).first else { return }
        let byExercise = Dictionary(
            session.sessionExercises.map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for we in workoutExercises {
            guard let se = byExercise[we.exerciseId] else { continue }
            if let ts = se.targetSets { targetSetsMap[we.id] = ts }
            if let rs = se.restBetweenSetsSeconds { restSecondsMap[we.id] = rs }
        }
    }

    /// Primer ejercicio cuyas series efectivas (sin calentamiento) no alcanzan su
    /// objetivo; si todos están completos (o no hay objetivo), el último ejercicio.
    private func firstIncompleteExerciseIndex() -> Int {
        for (idx, we) in workoutExercises.enumerated() {
            guard let target = targetSetsMap[we.id] else { continue }
            let done = we.exerciseSets.count(where: { !$0.isWarmup })
            if done < target { return idx }
        }
        return max(0, workoutExercises.count - 1)
    }

    // MARK: - Set logging

    /// Registra una serie y evalúa transición de fase según timerTriggerMode.
    public func recordSet(
        reps: Int,
        weight: Double?,
        weightUnit: WeightUnit,
        rpe: Int?,
        isWarmup: Bool
    ) async throws {
        guard let wkt = workout, let we = currentExercise else { return }

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

        let target = targetSetsMap[we.id] ?? Int.max
        let restSeconds = restSecondsMap[we.id] ?? 90

        guard let outcome = WorkoutPhaseTransition.evaluate(
            set: .init(number: setNumber, isWarmup: isWarmup),
            exercise: .init(
                target: target,
                restSeconds: restSeconds,
                index: currentExerciseIndex,
                total: workoutExercises.count
            ),
            triggerMode: timerTriggerMode
        ) else { return }

        phase = outcome.nextPhase
        logger
            .info(
                "Coordinator phase → \(String(describing: outcome.nextPhase)) (set \(setNumber), rest \(restSeconds)s)"
            )

        if let spec = outcome.restTimer {
            await timerService.start(
                workoutId: wkt.id,
                workoutName: wkt.name,
                type: spec.type,
                durationSeconds: spec.durationSeconds
            )
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
            logger.info("Coordinator phase → .active (undoLastSet)")
        }
    }

    // MARK: - Navigation

    public func advanceToNextExercise() {
        guard currentExerciseIndex < workoutExercises.count - 1 else { return }
        currentExerciseIndex += 1
        phase = .active
        // Capturar a variable local: el closure de Logger.info exige captura explícita;
        // swiftformat (redundantSelf) revierte `self.` así que evitamos el conflicto.
        let advancedTo = currentExerciseIndex
        logger.info("Coordinator phase → .active (advanced to exercise \(advancedTo))")
    }

    public func skipTimer() async {
        let wasRestingBetweenExercises = (phase == .restingBetweenExercises)
        await timerService.skip()
        phase = .active
        logger
            .info("Coordinator phase → .active (skipTimer, wasRestingBetweenExercises: \(wasRestingBetweenExercises))")
        if wasRestingBetweenExercises {
            advanceToNextExercise()
        }
    }

    // MARK: - Pause / Resume

    public func pause() async throws {
        guard let wkt = workout, phase == .active else { return }
        wkt.statusRaw = WorkoutStatus.paused.rawValue
        try modelContext.save()
        try await workoutRepository.update(wkt)
        elapsedTask?.cancel()
        phase = .paused
        logger.info("Coordinator phase → .paused")
    }

    public func resume() async throws {
        guard let wkt = workout, phase == .paused else { return }
        wkt.statusRaw = WorkoutStatus.active.rawValue
        try modelContext.save()
        try await workoutRepository.update(wkt)
        phase = .active
        logger.info("Coordinator phase → .active (resumed)")
        startElapsedTimer()
    }

    // MARK: - Finish

    public func finish() async throws {
        guard let wkt = workout else { return }
        elapsedTask?.cancel()
        await timerService.skip()

        wkt.durationSeconds = elapsedSeconds
        // Cierre LOCAL robusto: complete() marca completed y persiste en SwiftData
        // antes de encolar el sync. El push remoto es best-effort — un fallo de red
        // NO debe dejar el workout activo ni colgar el coordinador (bug #88).
        do {
            try await workoutRepository.complete(wkt)
        } catch {
            logger.error("finish: complete() falló al encolar sync; workout cerrado localmente igual: \(error)")
        }
        try? await syncEngine.pushPendingChanges()

        // Invocar Edge Function para calcular PRs (best-effort)
        try? await supabase.functions.invoke(
            "calc_personal_records",
            options: .init(body: ["workout_id": wkt.id.uuidString])
        )

        liveActivity.end()

        // Capture the completed workout ID BEFORE clearing state so that
        // WorkoutSummaryView can fetch it from SwiftData.
        completedWorkoutId = wkt.id

        workout = nil
        workoutExercises = []
        targetSetsMap = [:]
        restSecondsMap = [:]
        currentExerciseIndex = 0
        phase = .idle
        elapsedSeconds = 0
        logger.info("Coordinator phase → .idle (finished, summary ID: \(wkt.id))")
    }

    // MARK: - DrainCoordinatorProtocol conformance

    /// Returns the ID of the current active workout for drain matching.
    public var activeWorkoutId: UUID? {
        workout?.id
    }

    // MARK: - Helpers

    public var currentExercise: WorkoutExercise? {
        guard workoutExercises.indices.contains(currentExerciseIndex) else { return nil }
        return workoutExercises[currentExerciseIndex]
    }

    /// Expone el estado del timer de descanso para que las Views lo puedan leer directamente.
    /// Forwarding a `RestTimerService.state` — ambos son @MainActor @Observable.
    public var timerState: RestTimerState? {
        timerService.state
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
