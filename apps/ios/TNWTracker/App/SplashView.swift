import SwiftUI
import TNWTrackerKit

/// The launch screen brought to life: the same logo on the same colour, at the
/// same place, so the hand-over from the system's launch screen is invisible.
/// The dumbbell does one "rep" a second while the saved session is restored;
/// a small spinner shows only when that takes a while.
struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsProgress = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            logo

            if showsProgress {
                ProgressView()
                    .tint(.white)
                    .controlSize(.regular)
                    .offset(y: 110)
                    .accessibilityLabel(Text("splash.loading"))
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.Splash.screen)
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeIn(duration: 0.3)) { showsProgress = true }
        }
    }

    @ViewBuilder
    private var logo: some View {
        let image = Image("LaunchLogo").accessibilityHidden(true)
        if reduceMotion {
            image
        } else {
            image.keyframeAnimator(initialValue: Rep(), repeating: true) { content, rep in
                content
                    .scaleEffect(rep.scale)
                    .offset(y: rep.lift)
            } keyframes: { _ in
                KeyframeTrack(\.lift) {
                    SpringKeyframe(-10, duration: 0.25, spring: .snappy)
                    SpringKeyframe(0, duration: 0.35, spring: .bouncy)
                    LinearKeyframe(0, duration: 0.4)
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1.1, duration: 0.25, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                    LinearKeyframe(1.0, duration: 0.4)
                }
            }
        }
    }

    /// One lift of the dumbbell: up and a little bigger, then back.
    private struct Rep {
        var lift: CGFloat = 0
        var scale: CGFloat = 1
    }
}

#Preview {
    SplashView()
}
