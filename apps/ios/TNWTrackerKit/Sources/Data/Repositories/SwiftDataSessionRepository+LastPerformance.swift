import Foundation
import SwiftData

// "La última vez" for an exercise (fast-add-exercise S3 AC1, AC4).

extension SwiftDataSessionRepository {
    func lastPerformance(exerciseId: UUID) throws -> LastPerformance? {
        let done = EntryStatus.done.rawValue
        let descriptor = FetchDescriptor<SessionEntryModel>(
            predicate: #Predicate { entry in
                entry.statusRaw == done && entry.exercise?.id == exerciseId
            }
        )
        // An exercise has one done entry per session, so this reads a few rows,
        // not whole sessions.
        let candidates = try context.fetch(descriptor).compactMap { model -> (Date, SessionEntry)? in
            guard let completedAt = model.session?.completedAt, let entry = model.snapshot else { return nil }
            return (completedAt, entry)
        }
        for (completedAt, entry) in candidates.sorted(by: { $0.0 > $1.0 }) {
            let sets = entry.countedSets.map(\.values)
            if !sets.isEmpty {
                return LastPerformance(completedAt: completedAt, sets: sets)
            }
        }
        return nil
    }
}
