import Foundation
import Testing
@testable import TNWTrackerKit

/// S10: the widget reads only the next routine the app published for the
/// signed-in account, never an account's store.
@Suite("Widget snapshot (S10)")
struct NextRoutineSnapshotTests {
    @Test("S10 the widget shows what the app published, and nothing once it is removed")
    func widgetReadsThePublishedName() throws {
        let name = "next-routine-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot = NextRoutineSnapshot(defaults: defaults)

        snapshot.publish("Full Body A")
        #expect(NextSessionQuery.live(snapshot)?.nextSessionName() == "Full Body A")

        snapshot.publish(nil)
        #expect(NextSessionQuery.live(snapshot)?.nextSessionName() == nil)
    }

    @Test("S10 the widget's snapshot is in the app group it shares with the app")
    func sharedSnapshotIsInTheAppGroup() {
        #expect(NextRoutineSnapshot.shared() != nil)
    }
}
