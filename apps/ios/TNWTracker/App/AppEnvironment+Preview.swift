#if DEBUG
    import Foundation
    import TNWTrackerKit

    extension AppEnvironment {
        /// Environment for SwiftUI previews: in-memory store with the invented sample data.
        static func preview(withSampleData: Bool = true) -> AppEnvironment {
            let store: TrainingStore
            do {
                store = try TrainingStore(inMemory: true)
                if withSampleData {
                    try SampleTrainingData.loadIfEmpty(into: store)
                }
            } catch {
                fatalError("AppEnvironment.preview failed: \(error)")
            }
            return AppEnvironment.bootstrap(store: store)
        }
    }
#endif
