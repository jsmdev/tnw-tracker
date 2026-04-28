import Foundation
import SwiftData

/// Extensión de SyncEngineImpl que gestiona la suscripción Realtime
/// a la tabla rest_timers durante un workout activo.
public extension SyncEngineImpl {
    /// Inicia la suscripción Realtime para rest_timers de un workout concreto.
    /// Cuando llega un UPDATE, actualiza el RestTimer local en SwiftData.
    func startRealtimeRestTimers(
        workoutId: UUID,
        subscription: RealtimeRestTimerSubscription,
        modelContext: ModelContext
    ) async {
        await subscription.subscribe(workoutId: workoutId) { payload in
            let descriptor = FetchDescriptor<RestTimer>(
                predicate: #Predicate { $0.id == payload.id }
            )
            guard let timer = try? modelContext.fetch(descriptor).first else { return }
            timer.endsAt = payload.endsAt
            timer.isActive = payload.isActive
            try? modelContext.save()
        }
    }

    /// Detiene la suscripción Realtime.
    func stopRealtimeRestTimers(subscription: RealtimeRestTimerSubscription) async {
        await subscription.unsubscribe()
    }
}
