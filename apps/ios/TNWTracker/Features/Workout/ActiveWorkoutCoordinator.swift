import Foundation
import Observation
import os.log
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

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
    public internal(set) var currentExerciseIndex: Int = 0
    public internal(set) var phase: WorkoutPhase = .idle
    public private(set) var elapsedSeconds: Int = 0
    public var timerTriggerMode: TimerTriggerMode = .auto

    /// Set to the completed session ID just before state is cleared in `finish()`.
    /// Observers (ActiveWorkoutView) use this to trigger WorkoutSummaryView.
    public private(set) var completedWorkoutId: UUID?

    /// Targets of the routine the session was started from, by exercise.
    private(set) var targets: [UUID: RoutineItem] = [:]

    /// The rows still to do of the set table, by exercise, once the user changed
    /// them (edited, added, checked). Until then they follow `SetPlan`.
    var pendingRows: [UUID: [SetValues]] = [:]

    /// "La última vez" by exercise, read once per session (completed sessions only).
    @ObservationIgnored var lastPerformances: (sessionId: UUID, byExercise: [UUID: LastPerformance?])?

    // MARK: - Dependencies

    // Internal, not private: the extensions in `ActiveWorkoutCoordinator+*.swift` read them.

    let sessions: any SessionRepositoryProtocol
    private let routines: any RoutineRepositoryProtocol
    let exerciseSettings: any ExerciseSettingRepositoryProtocol
    /// "Descanso al cambiar de ejercicio" in seconds, or nil when it is off.
    private let changeExerciseRest: @MainActor () -> Int?
    /// Asks for a sync and returns at once: finishing never waits for it (S12).
    private let requestSync: @MainActor () -> Void
    let timerService: RestTimerService
    let liveActivity: any LiveActivityControlling
    /// The name of an exercise, for the Live Activity.
    let exerciseName: @MainActor (UUID) -> String?
    let now: () -> Date
    /// The state the Live Activity shows, to skip updates that change nothing.
    var publishedLiveActivityState: ActiveWorkoutAttributes.ContentState?

    /// The set whose rest timer is running (AC3.8: its rest taken is recorded when the rest ends).
    var restingSet: (setId: UUID, timerId: UUID)?
    /// The last set after which no timer ran; its rest is the time until the next set.
    var setWithoutTimer: (setId: UUID, completedAt: Date)?

    var elapsedTask: Task<Void, Never>?
    var undoLastSetId: UUID?
    /// The set whose rest the last set ended, and its `completedAt`: undo clears
    /// that rest and measures it again from there (D-T3k).
    var undoRestore: (setId: UUID, completedAt: Date)?
    var undoTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        sessions: any SessionRepositoryProtocol,
        routines: any RoutineRepositoryProtocol,
        exerciseSettings: any ExerciseSettingRepositoryProtocol,
        changeExerciseRest: @escaping @MainActor () -> Int?,
        requestSync: @escaping @MainActor () -> Void,
        timerService: RestTimerService,
        liveActivity: any LiveActivityControlling,
        exerciseName: @escaping @MainActor (UUID) -> String? = { _ in nil },
        now: @escaping () -> Date = Date.init
    ) {
        self.sessions = sessions
        self.routines = routines
        self.exerciseSettings = exerciseSettings
        self.changeExerciseRest = changeExerciseRest
        self.requestSync = requestSync
        self.timerService = timerService
        self.liveActivity = liveActivity
        self.exerciseName = exerciseName
        self.now = now
        timerService.onEnded = { [weak self] timer, ranSeconds in
            self?.restEnded(timer, ranSeconds: ranSeconds)
        }
        timerService.onExpired = { [weak self] in self?.restExpired() }
        timerService.onTick = { [weak self] _ in self?.publishLiveActivity() }
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
        startLiveActivity()
        startElapsedTimer()
    }

    // MARK: - Resume residual

    /// Reanuda una sesión residual en curso. La pausa no se persiste, así que la
    /// sesión reanudada vuelve siempre en `.active`.
    private func adoptExisting(_ existing: TrainingSession) {
        session = existing
        let routine = existing.routineId.flatMap { try? routines.routine(id: $0) }
        loadTargets(from: routine)
        currentExerciseIndex = resumeExerciseIndex()
        let startedAt = existing.startedAt ?? now()
        elapsedSeconds = max(0, Int(now().timeIntervalSince(startedAt)))
        phase = .active
        startLiveActivity()
        startElapsedTimer()
        logger.info("Coordinator adoptó sesión residual \(existing.id)")
    }

    private func loadTargets(from routine: Routine?) {
        targets = Dictionary(
            (routine?.items ?? []).map { ($0.exerciseId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Set logging

    /// Registra una serie manual del ejercicio actual y evalúa la transición de fase.
    /// A warm-up set is stored but does not count, and starts no phase transition.
    public func recordSet(reps: Int, weight: Weight?, rir: Int?, warmup: Bool = false) async throws {
        guard let current = session, let entry = currentEntry else { return }
        defer { publishLiveActivity() }
        // A rest still running ends with this set and records the time so far.
        let cutShort = restingSet
        await timerService.skip()
        let logged = try sessions.logManualSet(
            SetValues(reps: reps, weight: weight, rir: rir),
            warmup: warmup,
            exerciseId: entry.exerciseId,
            sessionId: current.id,
            at: now()
        )
        try refreshSession()
        undoRestore = cutShort.flatMap { cut in
            manualSet(cut.setId)?.completedAt.map { (cut.setId, $0) }
        }
        if let previous = setWithoutTimer {
            setWithoutTimer = nil
            undoRestore = previous
            let gap = (logged.completedAt ?? now()).timeIntervalSince(previous.completedAt)
            recordRest(max(0, Int(gap.rounded())), setId: previous.setId)
        }
        // Until a timer starts after it, the time until the next set is its rest.
        setWithoutTimer = (logged.id, logged.completedAt ?? now())

        startUndoWindow(for: logged.id)

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

    /// Ventana de undo de 5s
    private func startUndoWindow(for setId: UUID) {
        undoLastSetId = setId
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self.undoLastSetId = nil
            self.undoRestore = nil
        }
    }

    // MARK: - Navigation

    public func advanceToNextExercise() {
        guard currentExerciseIndex < entries.count - 1 else { return }
        currentExerciseIndex += 1
        phase = .active
        let advancedTo = currentExerciseIndex
        logger.info("Coordinator phase → .active (advanced to exercise \(advancedTo))")
        publishLiveActivity()
    }

    public func skipTimer() async {
        await timerService.skip()
        restOver("skipTimer")
    }

    /// The rest ran out on its own: the session moves on exactly as `skipTimer()` (#136 S1).
    private func restExpired() {
        guard phase == .restingBetweenSets || phase == .restingBetweenExercises else { return }
        restOver("rest expired")
    }

    /// The rest is over: back to `.active`, on the next exercise after a rest between exercises.
    private func restOver(_ reason: String) {
        let wasRestingBetweenExercises = (phase == .restingBetweenExercises)
        phase = .active
        logger.info("Coordinator phase → .active (\(reason), between exercises: \(wasRestingBetweenExercises))")
        if wasRestingBetweenExercises {
            advanceToNextExercise()
        }
        publishLiveActivity()
    }

    // MARK: - Pause / Resume

    public func pause() async throws {
        guard session != nil, phase == .active else { return }
        elapsedTask?.cancel()
        phase = .paused
        logger.info("Coordinator phase → .paused")
        publishLiveActivity()
    }

    public func resume() async throws {
        guard session != nil, phase == .paused else { return }
        phase = .active
        logger.info("Coordinator phase → .active (resumed)")
        startElapsedTimer()
        publishLiveActivity()
    }

    // MARK: - Finish

    /// What the last `finish()` did (nil before any finish).
    public private(set) var lastFinishOutcome: FinishOutcome?

    public func finish() async throws {
        guard let current = session else { return }
        elapsedTask?.cancel()
        // The last set of the session gets no rest taken.
        restingSet = nil
        setWithoutTimer = nil
        await timerService.skip()

        // Cierre LOCAL: la sesión se completa en el store antes de sincronizar.
        // The sync runs detached: finishing never waits for it nor fails because
        // of it (bug #88, S12); a failed sync keeps the session pending.
        // T6 (D7): una sesión sin series de trabajo (rutina o libre) nunca se
        // guarda: se descarta, sin resumen.
        let discard = !hasWorkingSets
        do {
            if discard {
                try sessions.discardSession(id: current.id)
            } else {
                try sessions.finishSession(id: current.id, at: now(), durationSeconds: elapsedSeconds)
            }
        } catch {
            logger.error("finish: cierre local falló: \(error)")
        }
        requestSync()

        liveActivity.end()

        if !discard {
            completedWorkoutId = current.id
        }
        clearWorkout()
        logger.info("Coordinator phase → .idle (finished, summary ID: \(current.id))")
        lastFinishOutcome = discard ? .discarded : .saved(current.id)
    }

    // MARK: - Helpers

    func clearWorkout() {
        session = nil
        targets = [:]
        pendingRows = [:]
        currentExerciseIndex = 0
        phase = .idle
        elapsedSeconds = 0
        publishedLiveActivityState = nil
    }

    func refreshSession() throws {
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
