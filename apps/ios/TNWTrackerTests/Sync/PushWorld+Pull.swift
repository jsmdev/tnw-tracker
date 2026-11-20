import Foundation
import Testing
@testable import TNWTrackerKit

/// Helpers for the pull tests: rows other clients write on the server (an
/// importer, another device of the same user), and comparable session shapes.
/// Invented data only.
@MainActor
extension PushWorld {
    static let provider = "machines-atlas"

    func ref(_ id: String) -> ExternalRef {
        ExternalRef(provider: Self.provider, id: id)
    }

    /// An engine over the same store and server with other paging settings.
    func engine(pageSize: Int, overlap: TimeInterval = 5) -> TrainingSyncEngine {
        TrainingSyncEngine(store: store, remote: server, userId: userId, pageSize: pageSize, pullOverlap: overlap)
    }

    /// A session an importer wrote on the server, on the day after `t0`: one
    /// done bench entry with one imported set. Nothing of it is on the device.
    func importedSessionRows(entryRef: String = "e-1") -> RemoteSessionAggregate {
        let day = t0.addingTimeInterval(86_400)
        let session = RemoteSessionRow(
            id: UUID(), userId: userId, name: "Machine day", startedAt: day,
            completedAt: day.addingTimeInterval(3_600), timeZone: "Europe/Madrid",
            durationSeconds: 3_000, externalRef: ref("2030-03-05/\(entryRef)")
        )
        let entry = RemoteEntryRow(
            id: UUID(), userId: userId, sessionId: session.id, position: 1, exerciseId: bench.id,
            status: .done, completedAt: day.addingTimeInterval(1_800), externalRef: ref(entryRef)
        )
        let set = importedSetRow(entryId: entry.id, ref: "\(entryRef)#1", reps: 10, at: day.addingTimeInterval(900))
        return RemoteSessionAggregate(session: session, entries: [entry], sets: [set])
    }

    func importedSetRow(entryId: UUID, ref id: String, reps: Int, position: Int = 1, at date: Date) -> RemoteSetRow {
        RemoteSetRow(
            id: UUID(), userId: userId, entryId: entryId, position: position, source: .imported,
            reps: reps, weight: .kg(50), completedAt: date, externalRef: ref(id)
        )
    }

    /// Writes a whole aggregate on the server as another client would.
    func writeOnServer(_ aggregate: RemoteSessionAggregate) async throws {
        try await server.insertOnServer(aggregate.session)
        for entry in aggregate.entries {
            try await server.insertOnServer(entry)
        }
        for set in aggregate.sets {
            try await server.insertOnServer(set)
        }
    }

    /// The server row of a pushed entry, as the server holds it now.
    func serverEntry(_ id: UUID) async throws -> RemoteEntryRow {
        try #require(await server.stored(RemoteEntryRow.self).first { $0.id == id })
    }

    func serverSet(_ id: UUID) async throws -> RemoteSetRow {
        try #require(await server.stored(RemoteSetRow.self).first { $0.id == id })
    }

    func session(_ id: UUID) throws -> TrainingSession {
        try #require(try store.sessions.session(id: id))
    }

    func completedSessions() throws -> [TrainingSession] {
        try store.sessions.completedSessions(in: DateInterval(start: .distantPast, end: .distantFuture))
    }

    func isPending(_ sessionId: UUID) throws -> Bool {
        try store.syncState.pendingSessions().contains { $0.id == sessionId }
    }
}

/// A session without its ids (its exercises' included) and decision times:
/// what two paths that create rows with their own ids must agree on.
struct SessionShape: Equatable {
    struct Entry: Equatable {
        var order: Int
        var status: EntryStatus
        var externalRef: ExternalRef?
        var keep: SetSource?
        var decidedBy: ReconciliationDecider?
        var sets: [SetShape]
    }

    struct SetShape: Equatable {
        var source: SetSource
        var order: Int
        var values: SetValues
        var externalRef: ExternalRef?
        var completedAt: Date?
        var superseded: Bool
        var warmup: Bool
    }

    var entries: [Entry]

    init(_ session: TrainingSession) {
        entries = session.entries.map { entry in
            Entry(
                order: entry.order, status: entry.status,
                externalRef: entry.externalRef, keep: entry.reconciliation?.keep,
                decidedBy: entry.reconciliation?.decidedBy,
                sets: entry.sets.map { set in
                    SetShape(
                        source: set.source, order: set.order, values: set.values, externalRef: set.externalRef,
                        completedAt: set.completedAt, superseded: set.superseded, warmup: set.warmup
                    )
                }
            )
        }
    }
}
