import Foundation
import Supabase

/// DTO para deserializar actualizaciones realtime de rest_timers.
public struct RestTimerRealtimePayload: Codable, Sendable {
    public let id: UUID
    public let workoutId: UUID
    public let timerTypeRaw: String
    public let durationSeconds: Int
    public let startedAt: Date
    public let endsAt: Date
    public let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case timerTypeRaw = "timer_type"
        case durationSeconds = "duration_seconds"
        case startedAt = "started_at"
        case endsAt = "ends_at"
        case isActive = "is_active"
    }
}

/// Suscripción Realtime al canal de rest_timers para un workout activo.
/// Solo se mantiene viva durante el workout; se cancela en `unsubscribe()`.
@MainActor
public final class RealtimeRestTimerSubscription {
    private let supabase: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var subscription: RealtimeSubscription?

    public init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    public func subscribe(
        workoutId: UUID,
        onUpdate: @MainActor @escaping (RestTimerRealtimePayload) -> Void
    ) async {
        let channelName = "rest_timers:\(workoutId.uuidString)"
        let ch = supabase.realtimeV2.channel(channelName)

        subscription = ch.onPostgresChange(
            UpdateAction.self,
            schema: "public",
            table: "rest_timers",
            filter: "workout_id=eq.\(workoutId.uuidString)"
        ) { change in
            guard
                let payload = try? change.decodeRecord(
                    as: RestTimerRealtimePayload.self,
                    decoder: AnyJSON.decoder
                )
            else { return }
            Task { @MainActor in onUpdate(payload) }
        }

        try? await ch.subscribeWithError()
        channel = ch
    }

    public func unsubscribe() async {
        subscription?.cancel()
        subscription = nil
        await channel?.unsubscribe()
        channel = nil
    }
}
