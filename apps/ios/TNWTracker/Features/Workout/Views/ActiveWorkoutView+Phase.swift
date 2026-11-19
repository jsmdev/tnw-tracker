import SwiftUI
import TNWTrackerKit

// Phase-driven parts of `ActiveWorkoutView`: rest timer, banners and pause/resume.

extension ActiveWorkoutView {
    // MARK: - Phase Section (PhaseAnimator for phase transitions)

    @ViewBuilder
    var phaseSection: some View {
        switch coordinator.phase {
        case .restingBetweenSets, .restingBetweenExercises:
            if let timerState = coordinator.timerState {
                RestTimerView(
                    state: timerState,
                    onSkip: { Task { await coordinator.skipTimer() } },
                    onAdjust: { seconds in Task { await coordinator.adjustTimer(by: seconds) } }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        case .finishing:
            finishingBanner
                .transition(.scale(scale: 1.05).combined(with: .opacity))
        case .paused:
            pausedBanner
                .transition(.opacity)
        default:
            EmptyView()
        }
    }

    private var finishingBanner: some View {
        Card {
            Label("active-workout.finishing-banner", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        }
    }

    private var pausedBanner: some View {
        Card {
            HStack {
                Image(systemName: "pause.circle.fill")
                    .symbolEffect(.pulse)
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("active-workout.paused-banner")
                    .font(.headline)
            }
        }
    }

    // MARK: - Pause / Resume

    @ViewBuilder
    var pauseResumeButton: some View {
        switch coordinator.phase {
        case .paused:
            Button {
                Task { try? await coordinator.resume() }
            } label: {
                Label("active-workout.controls.resume", systemImage: "play.fill")
                    .symbolEffect(.bounce, value: coordinator.phase == .paused)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        case .active, .restingBetweenSets, .restingBetweenExercises:
            Button {
                Task { try? await coordinator.pause() }
            } label: {
                Label("active-workout.controls.pause", systemImage: "pause.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        default:
            EmptyView()
        }
    }
}
