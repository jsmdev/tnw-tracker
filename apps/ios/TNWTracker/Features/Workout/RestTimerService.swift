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

/// Gestiona el timer de descanso en memoria: countdown tick a 1 Hz.
/// It never touches the Live Activity: the coordinator publishes the session's
/// state on each tick and ends the Live Activity only with the session (#136).
/// El timer no forma parte del formato de datos de entrenamiento, así que no se
/// persiste ni se sincroniza.
@MainActor
@Observable
public final class RestTimerService {
    public private(set) var state: RestTimerState?
    /// The workout name of the last timer started.
    public private(set) var workoutName: String = ""

    /// Called when a rest ends (finished or skipped) with the seconds it really
    /// ran, −15 s / +15 s included.
    public var onEnded: (@MainActor (_ timer: RestTimerState, _ ranSeconds: Int) -> Void)?

    /// Called after `onEnded` when a rest ran out on its own (not when it was
    /// skipped or stopped): the session moves on as if it had been skipped.
    public var onExpired: (@MainActor () async -> Void)?

    /// Called every second while a rest runs, with the seconds left.
    public var onTick: (@MainActor (_ secondsRemaining: Int) -> Void)?

    private var tickTask: Task<Void, Never>?
    private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
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
        onEnded?(current, Self.seconds(from: current.startedAt, to: current.endsAt))
        await onExpired?()
    }

    /// One second of the running rest: ends it when its time is up, otherwise
    /// reports the seconds left. The tick calls it every second.
    public func tick() async {
        guard let current = state else { return }
        let remaining = current.endsAt.timeIntervalSince(now())
        guard remaining > 0 else {
            await expireIfDue()
            return
        }
        let seconds = Self.secondsRemaining(until: current.endsAt, from: now())
        logger.debug("RestTimerService tick: \(seconds)s remaining")
        onTick?(seconds)
    }

    /// Whole seconds left until `end`, rounded up so a rest never shows 0 before it ends.
    public static func secondsRemaining(until end: Date, from start: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start).rounded(.up)))
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
                guard !Task.isCancelled, let self, state != nil else { break }
                await tick()
            }
        }
    }

    private func cancelTick() async {
        tickTask?.cancel()
        tickTask = nil
    }
}
