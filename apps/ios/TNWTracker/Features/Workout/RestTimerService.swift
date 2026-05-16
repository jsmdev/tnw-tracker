import Foundation
import Observation
import os.log
import Supabase
import SwiftData
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

/// Gestiona el timer de descanso: Supabase como fuente de verdad,
/// fallback local si offline, countdown tick a 1 Hz.
@MainActor
@Observable
public final class RestTimerService {
    public private(set) var state: RestTimerState?
    /// The workout name associated with the active timer; used by the Live Activity tick.
    public private(set) var workoutName: String = ""

    private var tickTask: Task<Void, Never>?
    private let supabase: SupabaseClient
    private let modelContext: ModelContext
    private let liveActivity: LiveActivityController

    private var isOnline: Bool {
        true // NWPathMonitor pendiente de implementar
    }

    public init(
        supabase: SupabaseClient,
        modelContext: ModelContext,
        liveActivity: LiveActivityController
    ) {
        self.supabase = supabase
        self.modelContext = modelContext
        self.liveActivity = liveActivity
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
        let startedAt = Date()
        let endsAt = startedAt.addingTimeInterval(TimeInterval(durationSeconds))

        let timerState = RestTimerState(
            id: timerId,
            workoutId: workoutId,
            type: type,
            startedAt: startedAt,
            endsAt: endsAt
        )
        state = timerState

        // Persiste localmente
        let localTimer = RestTimer(workoutId: workoutId, type: type, durationSeconds: durationSeconds)
        modelContext.insert(localTimer)
        try? modelContext.save()

        // Intenta subir a Supabase (fuente de verdad cross-device)
        if isOnline {
            let row: [String: AnyJSON] = [
                "id": .string(timerId.uuidString),
                "workout_id": .string(workoutId.uuidString),
                "timer_type": .string(type.rawValue),
                "duration_seconds": .integer(durationSeconds),
                "started_at": .string(startedAt.ISO8601Format()),
                "ends_at": .string(endsAt.ISO8601Format()),
                "is_active": .bool(true)
            ]
            try? await supabase.from("rest_timers").insert(row).execute()
        }

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

        // Marcar inactivo localmente
        let currentId = current.id
        let descriptor = FetchDescriptor<RestTimer>(
            predicate: #Predicate { $0.id == currentId }
        )
        if let timer = try? modelContext.fetch(descriptor).first {
            timer.isActive = false
            timer.pendingSyncOp = "update"
            try? modelContext.save()
        }

        if isOnline {
            try? await supabase
                .from("rest_timers")
                .update(["is_active": false])
                .eq("id", value: current.id.uuidString)
                .execute()
        }

        state = nil
        liveActivity.end()
    }

    public func extend(by seconds: Int) async {
        guard var current = state else { return }
        current.endsAt = current.endsAt.addingTimeInterval(TimeInterval(seconds))
        state = current

        let currentId = current.id
        let descriptor = FetchDescriptor<RestTimer>(
            predicate: #Predicate { $0.id == currentId }
        )
        if let timer = try? modelContext.fetch(descriptor).first {
            timer.endsAt = current.endsAt
            timer.pendingSyncOp = "update"
            try? modelContext.save()
        }

        if isOnline {
            try? await supabase
                .from("rest_timers")
                .update(["ends_at": current.endsAt.ISO8601Format()])
                .eq("id", value: current.id.uuidString)
                .execute()
        }
    }

    // MARK: - Private

    private func startTick() {
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let current = state else { break }

                if current.isExpired {
                    logger.info("RestTimerService timer expired: \(current.id.uuidString, privacy: .public)")
                    await handleExpiry()
                    break
                }

                logger.debug("RestTimerService tick: \(max(0, Int(current.remaining)))s remaining")
                let timerState = ActiveWorkoutAttributes.ContentState(
                    workoutName: workoutName,
                    currentExerciseName: nil,
                    restSecondsRemaining: max(0, Int(current.remaining)),
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

    private func handleExpiry() async {
        guard let current = state else { return }

        let currentId = current.id
        let descriptor = FetchDescriptor<RestTimer>(
            predicate: #Predicate { $0.id == currentId }
        )
        if let timer = try? modelContext.fetch(descriptor).first {
            timer.isActive = false
            timer.pendingSyncOp = "update"
            try? modelContext.save()
        }

        state = nil
        liveActivity.end()
    }
}
