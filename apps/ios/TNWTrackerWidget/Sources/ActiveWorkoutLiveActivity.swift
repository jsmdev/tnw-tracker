import ActivityKit
import SwiftUI
import TNWTrackerKit
import WidgetKit

struct ActiveWorkoutLiveActivityView: View {
    let context: ActivityViewContext<ActiveWorkoutAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.workoutId.uuidString)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let exercise = context.state.currentExerciseName {
                    Text(exercise)
                        .font(.headline)
                }
            }
            Spacer()
            if let seconds = context.state.restSecondsRemaining {
                VStack(alignment: .trailing) {
                    Text("Descanso")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timerText(seconds: seconds))
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(.blue)
                }
            } else {
                VStack(alignment: .trailing) {
                    Text("Series")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(context.state.completedSets)/\(context.state.totalSets)")
                        .font(.title2.bold())
                }
            }
        }
        .padding(.horizontal)
        .activityBackgroundTint(.black.opacity(0.8))
    }

    private func timerText(seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct ActiveWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiveWorkoutAttributes.self) { context in
            ActiveWorkoutLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if let exercise = context.state.currentExerciseName {
                        Text(exercise).font(.caption.bold())
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let seconds = context.state.restSecondsRemaining {
                        Text(timerText(seconds: seconds))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.blue)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Series: \(context.state.completedSets)/\(context.state.totalSets)")
                        .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                if let seconds = context.state.restSecondsRemaining {
                    Text(timerText(seconds: seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.blue)
            }
        }
    }

    private func timerText(seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
