import Foundation
import SwiftData

// "La última vez" and the history of an exercise (fast-add-exercise S3 AC1, AC4; S6).

extension SwiftDataSessionRepository {
    func lastPerformance(exerciseId: UUID) throws -> LastPerformance? {
        try exerciseHistory(exerciseId: exerciseId).first.map {
            LastPerformance(completedAt: $0.completedAt, sets: $0.sets)
        }
    }

    func exerciseHistory(exerciseId: UUID) throws -> [ExerciseHistoryItem] {
        let done = EntryStatus.done.rawValue
        let descriptor = FetchDescriptor<SessionEntryModel>(
            predicate: #Predicate { entry in
                entry.statusRaw == done && entry.exercise?.id == exerciseId
            }
        )
        // An exercise has one done entry per session, so this reads a few rows,
        // not whole sessions.
        return try context.fetch(descriptor)
            .compactMap { model -> ExerciseHistoryItem? in
                guard let session = model.session, let completedAt = session.completedAt,
                      let entry = model.snapshot else { return nil }
                let sets = entry.countedSets.map(\.values)
                guard !sets.isEmpty else { return nil }
                return ExerciseHistoryItem(
                    sessionId: session.id, sessionName: session.name, completedAt: completedAt, sets: sets
                )
            }
            .sorted { $0.completedAt > $1.completedAt }
    }
}
