#if DEBUG
    import Foundation
    import TNWTrackerKit

    extension AppEnvironment {
        /// Environment for SwiftUI previews: an account on an in-memory store with the invented sample data.
        static func preview(withSampleData: Bool = true) -> AppEnvironment {
            let userId = UUID()
            do {
                let store = try TrainingStore.inMemory()
                if withSampleData {
                    try SampleTrainingData.loadIfEmpty(into: store)
                }
                return try AppEnvironment(
                    userId: userId,
                    store: store,
                    remote: SupabaseTrainingRemoteStore(client: SupabaseClientProvider.shared.client, userId: userId),
                    intentInbox: IntentInbox.inMemory(),
                    liveActivity: LiveActivityController(requestsActivities: false)
                )
            } catch {
                fatalError("AppEnvironment.preview failed: \(error)")
            }
        }
    }
#endif
