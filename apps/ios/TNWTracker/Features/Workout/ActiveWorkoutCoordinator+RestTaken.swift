import Foundation
import os.log
import TNWTrackerKit

private let logger = Logger(subsystem: "com.tnwtracker", category: "coordinator")

extension ActiveWorkoutCoordinator {
    // MARK: - Rest taken (AC3.8)

    /// A rest ended (finished or skipped): the set before it gets the seconds it ran.
    func restEnded(_ timer: RestTimerState, ranSeconds: Int) {
        guard let resting = restingSet, resting.timerId == timer.id else { return }
        restingSet = nil
        recordRest(ranSeconds, setId: resting.setId)
    }

    /// Writes the rest taken after a manual set (nil clears it) through the
    /// repository's set update.
    func recordRest(_ seconds: Int?, setId: UUID) {
        guard var values = manualSet(setId)?.values else { return }
        values.restSeconds = seconds
        do {
            try sessions.updateManualSet(values, setId: setId)
            try refreshSession()
        } catch {
            logger.error("recordRest falló: \(error)")
        }
    }
}
