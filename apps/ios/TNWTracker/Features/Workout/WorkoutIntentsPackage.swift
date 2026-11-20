import AppIntents
import TNWTrackerKit

/// The app's App Intents: the Live Activity's, from `TNWTrackerKit`. A
/// `LiveActivityIntent` runs in the app process, so the app declares them too.
struct WorkoutIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [TNWTrackerKitIntents.self]
    }
}
