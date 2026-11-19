import Foundation
import SwiftData

/// Name of the routine the widget proposes next, with the same rule as the
/// Home card (`NextRoutineRule`, T5 AC5.2–AC5.3).
public struct NextSessionQuery {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Query over the app's on-disk store, or nil if it cannot be opened.
    public static func live() -> NextSessionQuery? {
        guard let container = try? ModelContainerFactory.makeContainer() else { return nil }
        return NextSessionQuery(container: container)
    }

    public func nextSessionName() -> String? {
        (try? ModelContext(container).nextRoutine())?.name
    }
}
