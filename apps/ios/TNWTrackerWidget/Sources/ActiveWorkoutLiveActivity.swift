import ActivityKit
import AppIntents
import SwiftUI
import TNWTrackerKit
import WidgetKit

// MARK: - Lock Screen View

struct ActiveWorkoutLiveActivityView: View {
    let context: ActivityViewContext<ActiveWorkoutAttributes>

    var body: some View {
        let isPaused = context.state.isPaused
        let isResting = context.state.restSecondsRemaining != nil

        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.workoutName)
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
                        Text("liveactivity.rest-label", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let duration = Duration.seconds(seconds)
                        Text(duration, format: .time(pattern: .minuteSecond))
                            .font(.title2.monospacedDigit().bold())
                            .foregroundStyle(.blue)
                    }
                } else {
                    VStack(alignment: .trailing) {
                        Text("liveactivity.sets-label", bundle: .main)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(context.state.completedSets)/\(context.state.totalSets)")
                            .font(.title2.bold())
                    }
                }
            }

            // Interactive buttons — lock screen Live Activity
            HStack(spacing: 12) {
                if isResting {
                    // Skip button — only during rest
                    Button(
                        intent: SkipRestIntent()
                    ) {
                        Label(
                            LocalizedStringResource("liveactivity.skip-button"),
                            systemImage: "forward.fill"
                        )
                        .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                if isPaused {
                    // Resume button — only when paused
                    Button(
                        intent: PauseWorkoutIntent()
                    ) {
                        Label(
                            LocalizedStringResource("liveactivity.resume-button"),
                            systemImage: "play.fill"
                        )
                        .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                } else if !isResting {
                    // Pause button — when active (not resting, not paused)
                    Button(
                        intent: PauseWorkoutIntent()
                    ) {
                        Label(
                            LocalizedStringResource("liveactivity.pause-button"),
                            systemImage: "pause.fill"
                        )
                        .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Spacer()

                // End button — always available
                Button(
                    intent: EndWorkoutIntent()
                ) {
                    Label(
                        LocalizedStringResource("liveactivity.end-button"),
                        systemImage: "xmark.circle.fill"
                    )
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.horizontal)
        .activityBackgroundTint(.black.opacity(0.8))
    }
}

// MARK: - Live Activity Widget

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
                        let duration = Duration.seconds(seconds)
                        Text(duration, format: .time(pattern: .minuteSecond))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundStyle(.blue)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        let isResting = context.state.restSecondsRemaining != nil
                        let isPaused = context.state.isPaused

                        if isResting {
                            Button(intent: SkipRestIntent()) {
                                Label(
                                    LocalizedStringResource("liveactivity.skip-button"),
                                    systemImage: "forward.fill"
                                )
                                .font(.caption2.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                        }

                        if isPaused {
                            Button(intent: PauseWorkoutIntent()) {
                                Label(
                                    LocalizedStringResource("liveactivity.resume-button"),
                                    systemImage: "play.fill"
                                )
                                .font(.caption2.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        } else if !isResting {
                            Button(intent: PauseWorkoutIntent()) {
                                Label(
                                    LocalizedStringResource("liveactivity.pause-button"),
                                    systemImage: "pause.fill"
                                )
                                .font(.caption2.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }

                        Spacer()

                        Button(intent: EndWorkoutIntent()) {
                            Label(
                                LocalizedStringResource("liveactivity.end-button"),
                                systemImage: "xmark.circle.fill"
                            )
                            .font(.caption2.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)

                        Text("\(context.state.completedSets)/\(context.state.totalSets)")
                            .font(.caption.bold())
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                if let seconds = context.state.restSecondsRemaining {
                    let duration = Duration.seconds(seconds)
                    Text(duration, format: .time(pattern: .minuteSecond))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.blue)
            }
        }
    }
}
