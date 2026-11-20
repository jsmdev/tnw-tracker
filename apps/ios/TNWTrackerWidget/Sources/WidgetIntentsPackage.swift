import AppIntents
import TNWTrackerKit

/// The widget extension's App Intents: the Live Activity's buttons, from `TNWTrackerKit`.
struct WidgetIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [TNWTrackerKitIntents.self]
    }
}
