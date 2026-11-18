import Foundation
import Observation
import os.log
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
/// Los datos viven en `SessionRepositoryProtocol`; el coordinador solo guarda
/// el snapshot más reciente de la sesión en curso.
/// La decisión pura de transición de fase tras un set vive en
/// `WorkoutPhaseTransition` (Kit) para poder testearla en aislamiento.
@MainActor
@Observable
public final class ActiveWorkoutCoordinator: DrainCoordinatorProtocol {
    // MARK: - Observed state

    /// Snapshot of the session in progress.
    public private(set) var session: TrainingSession?
    public private(set) var currentExerciseIndex: Int = 0
    public private(set) var phase: WorkoutPhase = .idle
    public private(set) var elapsedSeconds: Int = 0
    public var timerTriggerMode: TimerTriggerMode = .auto

    /// Set to the completed session ID just before state is cleared in `finish()`.
    /// Observers (ActiveWorkoutView) use this to trigger WorkoutSummaryView.
    public private(set) var completedWorkoutId: UUID?

    /// Targets of the routine the session was started from, by exercise.
    private var targets: [UUID: RoutineItem] = [:]

    // MARK: - Dependencies

    private let sessions: any SessionRepositoryProtocol
    private let routines: any RoutineRepositoryProtocol
    private let exerciseSettings: any ExerciseSettingRepositoryProtocol
    /// "Descanso al cambiar de ejercicio" in seconds, or nil when it is off.
    private let changeExerciseRest: @MainActor () -> Int?
    private let syncEngine: any SyncEngine
    private let timerService: RestTimerService
    private let liveActivity: LiveActivityController
    private let now: () -> Date

    /// The set whose rest timer is running (AC3.8: its rest taken is recorded when the rest ends).
    private var restingSet: (setId: UUID, timerId: UUID)?
    /// The last set after which no timer ran; its rest is the time until the next set.
    private var setWithoutTimer: (setId: UUID, completedAt: Date)?

    private var elapsedTask: Task<Void, Never>?
    private var undoLastSetId: UUID?
    private var undoTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        sessions: any SessionRepositoryProtocol,
        routines: any RoutineRepositoryProtocol,
        exerciseSettings: any ExerciseSettingRepositoryProtocol,
        changeExerciseRest: @escaping @MainActor () -> Int?,
        syncEngine: any SyncEngine,
        timerService: RestTimerService,
        liveActivity: LiveActivityController,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessions = sessions
        self.routines = routines
        self.exerciseSettings = exerciseSettings
        self.changeExerciseRest = changeExerciseRest
        self.syncEngine = syncEngine
        self.timerService = timerService
        self.liveActivity = liveActivity
        self.now = now
        timerService.onEnded = { [weak self] timer, ranSeconds in
            self?.restEnded(timer, ranSeconds: ranSeconds)
        }
    }

    // MARK: - Lifecycle

    /// Inicia el workout desde una rutina.
    /// Throws `TrainingDataError.notFound` when the routine does not exist.
    public func start(routineId: UUID) async throws {
        guard phase == .idle else { return }
        // Si quedó una sesión en curso sin terminar (p.ej. la app se cerró a mitad
        // o un finish() previo falló), la reanudamos en vez de crear otra (bug #88).
        if let existing = try sessions.activeSession() {
            adoptExisting(existing)
            return
        }
        guard let routine = try routines.routine(id: routineId) else {
            throw TrainingDataError.notFound
        }
        let started = try sessions.startSession(
            routineId: routine.id,
            name: routine.name,
            at: now(),
            timeZone: .current
        )
        begin(started, routine: routine)
        logger.info("Coordinator phase → .active (start from routine: \(routineId))")
    }

    /// Inicia un workout libre, sin rutina.
    public func startAdHoc(name: String) async throws {
        guard phase == .idle else { return }
        if let existing = try sessions.activeSession() {
            adoptExisting(existing)
            return
        }
        let started = try sessions.startSession(routineId: nil, name: name, at: now(), timeZone: .current)
        begin(started, routine: nil)
        logger.info("Coordinator phase → .active (ad-hoc)")
    }

    private func begin(_ started: TrainingSession, routine: Routine?) {
        session = started
        loadTargets(from: routine)
        currentExerciseIndex = 0
        elapsedSeconds = 0
        phase = .active
        liveActivity.start(workoutId: started.id, workoutName: started.name ?? "")
        startElapsedTimer()
    }

    // MARK: - Resume residual

    /// Reanuda una sesión residual en curso. La pausa no se persiste, así que la
    /// sesión reanudada vuelve siempre en `.active`.
    private func adoptExisting(_ existing: TrainingSession) {
        session = existing
        let routine = existing.routineId.flatMap { try? routines.routine(id: $0) }
        loadTargets(from: routine)
        currentExerciseIndex = firstIncompleteExerciseIndex()
        let startedAt = existing.startedAt ?? now()
        elapsedSeconds = max(0, Int(now().timeIntervalSince(startedAt)))
        phase = .active
        liveActivity.start(workoutId: existing.id, workoutName: existing.name ?? "")
        startElapsedTimer()
        logger.info("Coordinator adoptó sesión residual \(existing.id)")
    }

    private func loadTargets(from routine: Routine?) {
        targets = Dictionary(
            (routine?.items ?? []).map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Primer ejercicio cuyas series de trabajo (sin calentamiento) no alcanzan su objetivo; si todos
    /// están completos (o no hay objetivo), el último ejercicio.
    private func firstIncompleteExerciseIndex() -> Int {
        for (idx, entry) in entries.enumerated() {
            guard let target = target(for: entry)?.targetSets else { continue }
            if entry.workingManualSets.count < target { return idx }
        }
        return max(0, entries.count - 1)
    }

    private func target(for entry: SessionEntry) -> RoutineItem? {
        targets[entry.exerciseId] ?? entry.replacedExerciseId.flatMap { targets[$0] }
    }

    // MARK: - Set logging

    /// Registra una serie manual del ejercicio actual y evalúa la transición de fase.
    /// A warm-up set is stored but does not count, and starts no phase transition.
    public func recordSet(reps: Int, weight: Weight?, rir: Int?, warmup: Bool = false) async throws {
        guard let current = session, let entry = currentEntry else { return }
        // A rest still running ends with this set and records the time so far.
        await timerService.skip()
        let logged = try sessions.logManualSet(
            SetValues(reps: reps, weight: weight, rir: rir),
            warmup: warmup,
            exerciseId: entry.exerciseId,
            sessionId: current.id,
            at: now()
        )
        try refreshSession()
        if let previous = setWithoutTimer {
            setWithoutTimer = nil
            let gap = (logged.completedAt ?? now()).timeIntervalSince(previous.completedAt)
            recordRest(max(0, Int(gap.rounded())), setId: previous.setId)
        }
        // Until a timer starts after it, the time until the next set is its rest.
        setWithoutTimer = (logged.id, logged.completedAt ?? now())

        // Ventana de undo de 5s
        undoLastSetId = logged.id
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self.undoLastSetId = nil
        }

        let item = target(for: entry)
        guard let outcome = WorkoutPhaseTransition.evaluate(
            // Warm-ups do not count toward the target: number the working sets only.
            set: .init(number: currentEntry?.workingManualSets.count ?? logged.order, isWarmup: logged.warmup),
            exercise: .init(
                target: item?.targetSets ?? Int.max,
                restBetweenSets: RestPolicy.restBetweenSets(restSetting(for: entry.exerciseId)),
                restAfterExercise: changeExerciseRest(),
                index: currentExerciseIndex,
                total: entries.count
            ),
            triggerMode: timerTriggerMode
        ) else { return }

        logger.info("Coordinator phase → \(String(describing: outcome.nextPhase)) (set \(logged.order))")

        guard let spec = outcome.restTimer else {
            phase = outcome.nextPhase
            if outcome.nextPhase == .restingBetweenExercises {
                // "Descanso al cambiar de ejercicio" is off: go straight to the next exercise.
                advanceToNextExercise()
            }
            return
        }
        phase = outcome.nextPhase
        await timerService.start(
            workoutId: current.id,
            workoutName: current.name ?? "",
            type: spec.type,
            durationSeconds: spec.durationSeconds
        )
        if let timerId = timerService.state?.id {
            setWithoutTimer = nil
            restingSet = (logged.id, timerId)
        }
    }

    // MARK: - Rest taken (AC3.8)

    /// A rest ended (finished or skipped): the set before it gets the seconds it ran.
    private func restEnded(_ timer: RestTimerState, ranSeconds: Int) {
        guard let resting = restingSet, resting.timerId == timer.id else { return }
        restingSet = nil
        recordRest(ranSeconds, setId: resting.setId)
    }

    /// Writes the rest taken after a manual set through the repository's set update.
    private func recordRest(_ seconds: Int, setId: UUID) {
        let set = entries.lazy.flatMap(\.manualSets).first { $0.id == setId }
        guard var values = set?.values else { return }
        values.restSeconds = seconds
        do {
            try sessions.updateManualSet(values, setId: setId)
            try refreshSession()
        } catch {
            logger.error("recordRest falló: \(error)")
        }
    }

    // MARK: - Rest settings

    /// The exercise's "Descanso entre series" in force: the saved setting, else
    /// on with the routine item's rest, else 90 s.
    public func restSetting(for exerciseId: UUID) -> ExerciseSetting {
        let saved = try? exerciseSettings.setting(exerciseId: exerciseId)
        let routineRest = targets[exerciseId]?.restSeconds
            ?? entries.first { $0.exerciseId == exerciseId }.flatMap { target(for: $0)?.restSeconds }
        return RestPolicy.setting(exerciseId: exerciseId, saved: saved, routineRestSeconds: routineRest)
    }

    /// Saves the exercise's "Descanso entre series" for this and every later session.
    public func saveRestSetting(_ setting: ExerciseSetting) throws {
        try exerciseSettings.save(setting)
    }

    /// −15 s / +15 s on the running rest, the same for both timers.
    public func adjustTimer(by seconds: Int) async {
        await timerService.extend(by: seconds)
    }

    /// The user's warm-up annotation on a logged set of the session.
    public func setWarmup(_ warmup: Bool, setId: UUID) throws {
        try sessions.setWarmup(warmup, setId: setId)
        try refreshSession()
    }

    /// Deshace la última serie si todavía está en la ventana de undo.
    public func undoLastSet() async throws {
        guard let setId = undoLastSetId else { return }
        undoTask?.cancel()
        undoLastSetId = nil
        if restingSet?.setId == setId { restingSet = nil }
        if setWithoutTimer?.setId == setId { setWithoutTimer = nil }
        try sessions.deleteManualSet(id: setId)
        try refreshSession()
        await timerService.skip()
        if phase == .restingBetweenSets || phase == .restingBetweenExercises {
            phase = .active
            logger.info("Coordinator phase → .active (undoLastSet)")
        }
    }

    // MARK: - Navigation

    public func advanceToNextExercise() {
        guard currentExerciseIndex < entries.count - 1 else { return }
        currentExerciseIndex += 1
        phase = .active
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
        guard session != nil, phase == .active else { return }
        elapsedTask?.cancel()
        phase = .paused
        logger.info("Coordinator phase → .paused")
    }

    public func resume() async throws {
        guard session != nil, phase == .paused else { return }
        phase = .active
        logger.info("Coordinator phase → .active (resumed)")
        startElapsedTimer()
    }

    // MARK: - Finish

    public func finish() async throws {
        guard let current = session else { return }
        elapsedTask?.cancel()
        // The last set of the session gets no rest taken.
        restingSet = nil
        setWithoutTimer = nil
        await timerService.skip()

        // Cierre LOCAL: la sesión se completa en el store antes de sincronizar.
        // El sync remoto es best-effort — un fallo NO debe dejar la sesión en
        // curso ni colgar el coordinador (bug #88).
        // El formato exige al menos una entrada: una sesión libre terminada sin
        // ejercicios se descarta en vez de completarse.
        let isEmpty = (try? sessions.session(id: current.id))?.entries.isEmpty ?? current.entries.isEmpty
        do {
            if isEmpty {
                try sessions.discardSession(id: current.id)
            } else {
                try sessions.finishSession(id: current.id, at: now(), durationSeconds: elapsedSeconds)
            }
        } catch {
            logger.error("finish: cierre local falló: \(error)")
        }
        do {
            try await syncEngine.fullSync()
        } catch {
            logger.error("finish: sync falló; sesión cerrada localmente igual: \(error)")
        }

        liveActivity.end()

        completedWorkoutId = current.id
        session = nil
        targets = [:]
        currentExerciseIndex = 0
        phase = .idle
        elapsedSeconds = 0
        logger.info("Coordinator phase → .idle (finished, summary ID: \(current.id))")
    }

    // MARK: - DrainCoordinatorProtocol conformance

    public var activeWorkoutId: UUID? {
        session?.id
    }

    // MARK: - Helpers

    /// Entries the user works through, in session order. Removed entries are hidden.
    public var entries: [SessionEntry] {
        (session?.entries ?? []).filter { $0.status != .removed }
    }

    public var currentEntry: SessionEntry? {
        let list = entries
        guard list.indices.contains(currentExerciseIndex) else { return nil }
        return list[currentExerciseIndex]
    }

    /// Expone el estado del timer de descanso para que las Views lo puedan leer directamente.
    public var timerState: RestTimerState? {
        timerService.state
    }

    private func refreshSession() throws {
        guard let id = session?.id else { return }
        session = try sessions.session(id: id)
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
