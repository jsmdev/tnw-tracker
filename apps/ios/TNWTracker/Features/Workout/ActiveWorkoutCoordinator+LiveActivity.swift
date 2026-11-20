import Foundation
import TNWTrackerKit

// The workout's Live Activity lasts the whole session (#136 S2): it starts with
// the session, shows its state after every change, and ends only in `finish()`
// and `abandon()`. The rest timer never ends it.

extension ActiveWorkoutCoordinator {
    /// What the Live Activity shows for the session in progress, or nil without one.
    var liveActivityState: ActiveWorkoutAttributes.ContentState? {
        guard let current = session else { return nil }
        let progress = setProgress
        return ActiveWorkoutAttributes.ContentState(
            workoutName: current.name ?? "",
            currentExerciseName: currentEntry.flatMap { exerciseName($0.exerciseId) },
            restSecondsRemaining: timerService.state.map {
                RestTimerService.secondsRemaining(until: $0.endsAt, from: now())
            },
            completedSets: progress.completed,
            totalSets: progress.total,
            isPaused: phase == .paused
        )
    }

    /// Working sets logged in the session, and the sets it has in all (#136 S4):
    /// each exercise counts its target sets, or the sets logged when there are
    /// more or it has no target (a free session), so the total is never below
    /// the sets done. Warm-ups do not count, as for the routine's target.
    var setProgress: (completed: Int, total: Int) {
        entries.reduce(into: (completed: 0, total: 0)) { progress, entry in
            let done = entry.workingManualSets.count
            progress.completed += done
            progress.total += max(done, target(for: entry)?.targetSets ?? 0)
        }
    }

    func startLiveActivity() {
        guard let current = session, let state = liveActivityState else { return }
        liveActivity.start(workoutId: current.id, state: state)
        publishedLiveActivityState = state
    }

    /// Shows the session's current state on the Live Activity, when it changed.
    func publishLiveActivity() {
        guard let state = liveActivityState, state != publishedLiveActivityState else { return }
        liveActivity.update(state: state)
        publishedLiveActivityState = state
    }
}
