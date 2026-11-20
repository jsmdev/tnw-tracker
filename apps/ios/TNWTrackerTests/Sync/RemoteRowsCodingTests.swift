import Foundation
import Testing
@testable import TNWTrackerKit

@Suite("Remote rows coding")
struct RemoteRowsCodingTests {
    /// An upsert only updates the columns it sends, so `nil` must go as `null`;
    /// the server's own timestamps never go.
    @Test func encodingSendsEveryClientColumnAndNoServerTimestamp() throws {
        let set = RemoteSetRow(
            id: UUID(), userId: UUID(), entryId: UUID(), position: 1, source: .manual, reps: 5,
            updatedAt: "2026-11-19T10:00:00.123456+00:00"
        )

        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(set)) as? [String: Any])

        #expect(Set(object.keys) == [
            "id", "user_id", "entry_id", "position", "source", "reps", "weight", "weight_unit",
            "duration_seconds", "distance_meters", "rir", "rest_seconds", "completed_at",
            "superseded", "warmup", "external_provider", "external_id"
        ])
        #expect(object["rir"] is NSNull)
        #expect(object["weight"] is NSNull)
        #expect(object["external_id"] is NSNull)
        #expect(object["reps"] as? Int == 5)
    }

    /// `updated_at` is kept as the server's text: it is half of the cursor, and
    /// a `Date` would drop the microseconds.
    @Test func decodingKeepsServerTimestampTextAndFlattenedValues() throws {
        let json = Data("""
        {"id":"30000000-0000-4000-8000-000000000001","user_id":"00000000-0000-4000-8000-0000000000a1",
         "entry_id":"20000000-0000-4000-8000-000000000001","position":2,"source":"imported","reps":8,
         "weight":82.5,"weight_unit":"kg","duration_seconds":null,"distance_meters":null,"rir":null,
         "rest_seconds":null,"completed_at":null,"superseded":true,"warmup":false,
         "external_provider":"machines-atlas","external_id":"set-1",
         "created_at":"2026-11-19T10:00:00.123456+00:00","updated_at":"2026-11-19T10:00:00.123456+00:00"}
        """.utf8)

        let set = try JSONDecoder().decode(RemoteSetRow.self, from: json)

        #expect(set.updatedAt == "2026-11-19T10:00:00.123456+00:00")
        #expect(set.weight == Weight(value: 82.5, unit: .kg))
        #expect(set.externalRef == ExternalRef(provider: "machines-atlas", id: "set-1"))
        #expect(set.source == .imported)
        #expect(set.superseded)
        #expect(set.position == 2)
    }

    @Test func everyRowSurvivesARoundTrip() throws {
        var aggregate = TrainingRemoteStoreContract.finishedSession(for: UUID())
        let ref = ExternalRef(provider: "machines-atlas", id: "item-1")
        aggregate.session.externalRef = ref
        aggregate.session.routineId = UUID()
        aggregate.entries[0].externalRef = ref
        aggregate.entries[0].replacedExerciseId = UUID()
        aggregate.entries[0].reconciliationKeep = .imported
        aggregate.entries[0].reconciliationDecidedBy = .user
        aggregate.entries[0].reconciliationDecidedAt = TrainingRemoteStoreContract.date(minute: 50)
        aggregate.sets[0].durationSeconds = 30
        aggregate.sets[0].superseded = true
        aggregate.sets[0].externalRef = ref
        let coder = (JSONEncoder(), JSONDecoder())

        let session = try coder.1.decode(RemoteSessionRow.self, from: coder.0.encode(aggregate.session))
        let entries = try coder.1.decode([RemoteEntryRow].self, from: coder.0.encode(aggregate.entries))
        let sets = try coder.1.decode([RemoteSetRow].self, from: coder.0.encode(aggregate.sets))

        #expect(session == aggregate.session)
        #expect(entries == aggregate.entries)
        #expect(sets == aggregate.sets)
    }

    @Test func pageCursorIsTheLastRow() {
        let rows = (1 ... 2).map { index in
            RemoteSessionRow(
                id: UUID(), userId: UUID(), completedAt: .now, timeZone: "UTC",
                updatedAt: "2026-11-19T10:00:0\(index).000000+00:00"
            )
        }

        let full = RemotePage(rows: rows, limit: 2)
        let short = RemotePage(rows: rows, limit: 3)
        let empty = RemotePage<RemoteSessionRow>(rows: [], limit: 2)

        #expect(full.next == RemoteCursor(updatedAt: "2026-11-19T10:00:02.000000+00:00", id: rows[1].id))
        #expect(full.mayHaveMore)
        #expect(short.mayHaveMore == false)
        #expect(empty.next == nil)
        #expect(empty.mayHaveMore == false)
    }
}
