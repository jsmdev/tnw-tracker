import Foundation
import SwiftData

// Adding an exercise to the session in progress before any set (fast-add-exercise S4).

extension SwiftDataSessionRepository {
    func addEntry(exerciseId: UUID, sessionId: UUID) throws -> SessionEntry {
        let session = try openSession(sessionId)
        guard let exercise = try context.fetchExercise(id: exerciseId) else { throw TrainingDataError.notFound }
        let removed = EntryStatus.removed.rawValue
        if let existing = session.entries.first(where: { $0.exercise?.id == exerciseId && $0.statusRaw != removed }),
           let snapshot = existing.snapshot {
            return snapshot
        }
        let order = (session.entries.map(\.order).max() ?? 0) + 1
        let entry = SessionEntryModel(id: UUID(), order: order, statusRaw: EntryStatus.skipped.rawValue)
        context.insert(entry)
        entry.exercise = exercise
        session.entries.append(entry)
        session.markChanged()
        try context.save()
        guard let snapshot = entry.snapshot else { throw TrainingDataError.notFound }
        return snapshot
    }
}
