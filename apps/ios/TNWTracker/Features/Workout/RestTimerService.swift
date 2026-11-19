import Foundation
import Observation
import os.log
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

/// Estado observable del timer de descanso activo.
public struct RestTimerState: Sendable, Equatable {
    public let id: UUID
    public let workoutId: UUID
    public let type: TimerType
    public let startedAt: Date
    public var endsAt: Date

    public var remaining: TimeInterval {
        endsAt.timeIntervalSinceNow
    }

    public var isExpired: Bool {
        remaining <= 0
    }
}

/// Gestiona el timer de descanso en memoria: countdown tick a 1 Hz y Live Activity.
/// El timer no forma parte del formato de datos de entrenamiento, así que no se
/// persiste ni se sincroniza.
@MainActor
@Observable
public final class RestTimerService {
    public private(set) var state: RestTimerState?
    /// The workout name associated with the active timer; used by the Live Activity tick.
    public private(set) var workoutName: String = ""

    /// Called when a rest ends (finished or skipped) with the seconds it really
    /// ran, −15 s / +15 s included.
    public var onEnded: (@MainActor (_ timer: RestTimerState, _ ranSeconds: Int) -> Void)?

    private var tickTask: Task<Void, Never>?
    private let liveActivity: LiveActivityController
    private let now: () -> Date

    public init(liveActivity: LiveActivityController, now: @escaping () -> Date = Date.init) {
        self.liveActivity = liveActivity
        self.now = now
    }

    // MARK: - Public API

    public func start(
        workoutId: UUID,
        workoutName: String,
        type: TimerType,
        durationSeconds: Int
    ) async {
        // Store name for Live Activity tick updates
        self.workoutName = workoutName
        // Cancelar timer anterior si hubiera
        await cancelTick()

        let timerId = UUID()
        let startedAt = now()
        let endsAt = startedAt.addingTimeInterval(TimeInterval(durationSeconds))

        let timerState = RestTimerState(
            id: timerId,
            workoutId: workoutId,
            type: type,
            startedAt: startedAt,
            endsAt: endsAt
        )
        state = timerState

        logger.info(
            """
            RestTimerService started: workout=\(workoutId.uuidString, privacy: .public) \
            type=\(type.rawValue) duration=\(durationSeconds)s
            """
        )
        startTick()
    }

    public func skip() async {
        guard let current = state else { return }
        logger.info("RestTimerService skip: timer \(current.id.uuidString, privacy: .public)")
        await cancelTick()

        state = nil
        liveActivity.end()
        onEnded?(current, Self.seconds(from: current.startedAt, to: min(now(), current.endsAt)))
    }

    /// Drops the rest without ending it: no rest taken is reported (`onEnded`
    /// is not called). For a workout left where it is.
    public func stop() async {
        await cancelTick()
        state = nil
    }

    /// Ends the rest when its time is up. The tick calls it every second.
    public func expireIfDue() async {
        guard let current = state, now() >= current.endsAt else { return }
        logger.info("RestTimerService timer expired: \(current.id.uuidString, privacy: .public)")
        await cancelTick()
        state = nil
        liveActivity.end()
        onEnded?(current, Self.seconds(from: current.startedAt, to: current.endsAt))
    }

    private static func seconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start).rounded()))
    }

    /// Adds (or, when negative, removes) time from the running rest. The rest
    /// never ends before now.
    public func extend(by seconds: Int) async {
        guard var current = state else { return }
        current.endsAt = max(now(), current.endsAt.addingTimeInterval(TimeInterval(seconds)))
        state = current
    }

    // MARK: - Private

    private func startTick() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let current = state else { break }

                if now() >= current.endsAt {
                    tickTask = nil
                    await expireIfDue()
                    break
                }

                let remaining = current.endsAt.timeIntervalSince(now())
                logger.debug("RestTimerService tick: \(max(0, Int(remaining)))s remaining")
                let timerState = ActiveWorkoutAttributes.ContentState(
                    workoutName: workoutName,
                    currentExerciseName: nil,
                    restSecondsRemaining: max(0, Int(remaining)),
                    completedSets: 0,
                    totalSets: 0
                )
                liveActivity.update(state: timerState)
            }
        }
    }

    private func cancelTick() async {
        tickTask?.cancel()
        tickTask = nil
    }
}
