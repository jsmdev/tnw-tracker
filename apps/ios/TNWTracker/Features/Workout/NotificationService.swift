import Foundation
import UserNotifications

/// Gestiona notificaciones locales para el timer de descanso.
/// No usa APNs — solo UNUserNotificationCenter (MVP).
@MainActor
public final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    /// Solicita permiso al usuario (llamar en onboarding).
    public func requestAuthorization() async {
        try? await center.requestAuthorization(options: [.alert, .sound])
    }

    /// Programa una notificación local para cuando expire el timer.
    /// - Parameters:
    ///   - timerId: identificador único para poder cancelarla.
    ///   - endsAt: momento en que se debe disparar.
    ///   - timerType: "entre series" o "entre ejercicios".
    public func scheduleTimerNotification(timerId: UUID, endsAt: Date, timerType: String) {
        let interval = endsAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "¡Tiempo de descanso terminado!"
        content.body = "Continúa con el siguiente \(timerType)."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: timerId.uuidString,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    /// Cancela la notificación de un timer concreto (al hacer skip).
    public func cancelNotification(timerId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [timerId.uuidString])
    }

    /// Cancela todas las notificaciones pendientes de timers.
    public func cancelAllTimerNotifications() {
        center.removeAllPendingNotificationRequests()
    }
}
