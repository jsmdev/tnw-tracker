import Foundation
import SwiftData

/// Name of the routine the widget proposes next.
/// Today it is the first routine by name; choosing the next routine from the
/// history is a later version (format O12).
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
        var descriptor = FetchDescriptor<RoutineModel>(sortBy: [SortDescriptor(\.name)])
        descriptor.fetchLimit = 1
        return (try? ModelContext(container).fetch(descriptor))?.first?.name
    }
}
