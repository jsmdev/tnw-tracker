import Foundation
import SwiftData

/// Name of the routine the widget proposes next, with the same rule as the
/// Home card (`NextRoutineRule`, T5 AC5.2–AC5.3).
public struct NextSessionQuery {
    private let read: () -> String?

    /// The next routine of the store in `container`.
    public init(container: ModelContainer) {
        read = { (try? ModelContext(container).nextRoutine())?.name }
    }

    private init(read: @escaping () -> String?) {
        self.read = read
    }

    /// What the widget shows: the name the app published for the signed-in
    /// account (`NextRoutineSnapshot`), none while signed out (S10). The widget
    /// process never opens an account's store. Nil without the app group.
    public static func live(_ snapshot: NextRoutineSnapshot? = .shared()) -> NextSessionQuery? {
        snapshot.map { snapshot in NextSessionQuery { snapshot.routineName } }
    }

    public func nextSessionName() -> String? {
        read()
    }
}

/// The next routine's name that the app publishes for the widget in the app
/// group: only the signed-in account's, removed when it signs out (S10).
public struct NextRoutineSnapshot {
    static let key = "widget.next-routine-name"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The snapshot in the app group the widget reads.
    public static func shared() -> NextRoutineSnapshot? {
        UserDefaults(suiteName: ModelContainerFactory.appGroup).map(NextRoutineSnapshot.init)
    }

    public var routineName: String? {
        defaults.string(forKey: Self.key)
    }

    /// Publishes `name`, or removes the snapshot when it is nil.
    public func publish(_ name: String?) {
        if let name {
            defaults.set(name, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
