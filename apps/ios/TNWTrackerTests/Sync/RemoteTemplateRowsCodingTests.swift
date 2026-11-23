import Foundation
import Testing
@testable import TNWTrackerKit

@Suite("Remote exercise and routine rows coding")
struct RemoteTemplateRowsCodingTests {
    private let userId = UUID()
    private let ref = ExternalRef(provider: "machines-atlas", id: "item-1")

    /// Every client column goes, `nil` as `null`, so an upsert can clear it; the
    /// server's timestamps never go.
    @Test func encodingSendsEveryClientColumnAndNoServerTimestamp() throws {
        let exercise = RemoteExerciseRow(
            id: UUID(), userId: userId, name: "Plank", type: .bodyweight, updatedAt: "2026-11-19T10:00:00+00:00"
        )
        let item = RemoteRoutineItemRow(
            id: UUID(), userId: userId, routineId: UUID(), position: 1, exerciseId: UUID(), updatedAt: "x"
        )
        let routine = RemoteRoutineRow(id: UUID(), userId: userId, name: "Core", updatedAt: "x")
        let group = RemoteMuscleGroupRow(exerciseId: UUID(), muscle: .core, role: .primary, position: 2)

        let columns = try [encoded(exercise), encoded(item), encoded(routine), encoded(group)]

        #expect(Set(columns[0].keys) == [
            "id", "user_id", "name", "type", "equipment", "setup_steps", "execution_steps", "tips",
            "image_uri", "video_uri", "external_provider", "external_id"
        ])
        #expect(Set(columns[1].keys) == [
            "id", "user_id", "routine_id", "position", "exercise_id", "target_sets", "target_reps_min",
            "target_reps_max", "target_weight", "target_weight_unit", "target_duration_seconds", "rest_seconds",
            "notes"
        ])
        #expect(Set(columns[2].keys) == [
            "id", "user_id", "name", "description", "is_favorite", "external_provider", "external_id"
        ])
        #expect(Set(columns[3].keys) == ["id", "exercise_id", "muscle", "role", "position"])
        #expect(columns[3]["position"] as? Int == 2)
        #expect(columns[0]["setup_steps"] is NSNull)
        #expect(columns[1]["target_weight_unit"] is NSNull)
        #expect(columns[2]["description"] is NSNull)
        #expect(columns[3]["muscle"] as? String == "core")
    }

    @Test func everyRowSurvivesARoundTrip() throws {
        let exercise = RemoteExerciseRow(
            id: UUID(), userId: userId, name: "Cable fly", type: .strength, equipment: .machine,
            setupSteps: ["Set the pulleys"], executionSteps: ["Pull"], tips: ["Breathe"],
            imageURI: "https://example.test/a.png", videoURI: "https://example.test/a.mp4", externalRef: ref
        )
        let item = RemoteRoutineItemRow(
            id: UUID(), userId: userId, routineId: UUID(), position: 2, exerciseId: UUID(), targetSets: 3,
            targetReps: RepRange(min: 8, max: 12), targetWeight: Weight(value: 12.5, unit: .lb),
            targetDurationSeconds: 30, restSeconds: 60, notes: "Slow"
        )
        let routine = RemoteRoutineRow(
            id: UUID(), userId: userId, name: "Push", description: "Chest", isFavorite: true, externalRef: ref
        )
        let group = RemoteMuscleGroupRow(exerciseId: UUID(), muscle: .chest, role: .secondary, position: 3)

        #expect(try roundTrip(exercise) == exercise)
        #expect(try roundTrip(item) == item)
        #expect(try roundTrip(routine) == routine)
        #expect(try roundTrip(group) == group)
    }

    /// The server's catalogue rows have no owner and the app reads them as such.
    @Test func catalogueExerciseDecodesWithoutOwner() throws {
        let json = Data("""
        {"id":"e1000001-0000-4000-8000-000000000001","user_id":null,"name":"Bench Press","type":"strength",
         "equipment":"free_weights","setup_steps":null,"execution_steps":null,"tips":null,"image_uri":null,
         "video_uri":null,"external_provider":null,"external_id":null,"updated_at":"2026-11-19T10:00:00+00:00"}
        """.utf8)

        let exercise = try JSONDecoder().decode(RemoteExerciseRow.self, from: json)

        #expect(exercise.id == TrainingRemoteStoreContract.benchPress)
        #expect(exercise.userId == nil)
        #expect(exercise.equipment == .freeWeights)
        #expect(exercise.externalRef == nil)
        #expect(exercise.updatedAt == "2026-11-19T10:00:00+00:00")
    }

    /// Child rows without a local id get the same id for the same natural key,
    /// and a different one for any other.
    @Test func derivedChildIdsFollowTheNaturalKey() {
        let exercise = UUID()
        let routine = UUID()

        let group = RemoteMuscleGroupRow(exerciseId: exercise, muscle: .chest, role: .primary)

        #expect(group.id == RemoteMuscleGroupRow(exerciseId: exercise, muscle: .chest, role: .primary).id)
        #expect(group.id != RemoteMuscleGroupRow(exerciseId: exercise, muscle: .chest, role: .secondary).id)
        #expect(group.id != RemoteMuscleGroupRow(exerciseId: exercise, muscle: .back, role: .primary).id)
        #expect(group.id != RemoteMuscleGroupRow(exerciseId: UUID(), muscle: .chest, role: .primary).id)
        #expect(group.id == RemoteMuscleGroupRow(exerciseId: exercise, muscle: .chest, role: .primary, position: 4).id)
        #expect(RemoteRoutineItemRow.id(routineId: routine, position: 1)
            == RemoteRoutineItemRow.id(routineId: routine, position: 1))
        #expect(RemoteRoutineItemRow.id(routineId: routine, position: 1)
            != RemoteRoutineItemRow.id(routineId: routine, position: 2))
        // Version 5, RFC 4122 variant.
        #expect(group.id.uuidString.dropFirst(14).first == "5")
        #expect("89AB".contains(group.id.uuidString.dropFirst(19).first ?? "-"))
    }

    @Test("an exercise setting is keyed by its exercise: it sends every column it owns and reads the server's back")
    func exerciseSettingColumns() throws {
        let exerciseId = UUID()
        let userId = UUID()
        let setting = RemoteExerciseSettingRow(
            exerciseId: exerciseId, userId: userId, restEnabled: false, restSeconds: 75
        )

        let columns = try encoded(setting)

        #expect(Set(columns.keys) == ["exercise_id", "user_id", "rest_enabled", "rest_seconds"])
        #expect(columns["exercise_id"] as? String == exerciseId.uuidString)
        #expect(columns["rest_enabled"] as? Bool == false)
        #expect(columns["rest_seconds"] as? Int == 75)
        #expect(try roundTrip(setting) == setting)
        let server = Data("""
        {"user_id":"\(userId.uuidString.lowercased())","exercise_id":"\(exerciseId.uuidString.lowercased())",
         "rest_enabled":true,"rest_seconds":90,"created_at":"2026-01-01T00:00:00+00:00",
         "updated_at":"2026-01-01T00:00:01.5+00:00"}
        """.utf8)
        let read = try JSONDecoder().decode(RemoteExerciseSettingRow.self, from: server)
        #expect(read == RemoteExerciseSettingRow(
            exerciseId: exerciseId, userId: userId, restEnabled: true, restSeconds: 90,
            updatedAt: "2026-01-01T00:00:01.5+00:00"
        ))
        #expect(RemoteTable.exerciseSettings.keyColumn == "exercise_id")
        #expect(RemoteTable.exerciseSettings.conflictTarget == "user_id,exercise_id")
        #expect(RemoteTable.sets.keyColumn == "id")
        #expect(RemoteTable.sets.conflictTarget == "id")
        #expect(RemoteTable.exerciseMuscleGroups.parentColumn == "exercise_id")
        #expect(RemoteTable.routineItems.parentColumn == "routine_id")
        #expect(RemoteTable.sessions.parentColumn == nil)
    }

    // MARK: - Related links (#182 S9, S10, format 1.2)

    /// Curated on the server: the app reads them and never sends the column, so
    /// a push cannot erase them.
    @Test func relatedLinksAreReadButNeverSent() throws {
        let json = Data("""
        {"id":"e1000001-0000-4000-8000-000000000001","user_id":null,"name":"Bench Press","type":"strength",
         "related_links":[{"title":"Setup","url":"https://video.example/a","source":"Example"},
                           {"title":"Range","url":"https://video.example/b","source":"Example"}]}
        """.utf8)

        var exercise = try JSONDecoder().decode(RemoteExerciseRow.self, from: json)

        #expect(exercise.relatedLinks == [
            RelatedLink(title: "Setup", url: "https://video.example/a", source: "Example"),
            RelatedLink(title: "Range", url: "https://video.example/b", source: "Example")
        ])
        #expect(try encoded(exercise)["related_links"] == nil)
        exercise.relatedLinks = nil
        #expect(try encoded(exercise)["related_links"] == nil, "nil is not sent as null either")
    }

    @Test func anExerciseWithNullRelatedLinksDecodesWithNone() throws {
        let json = Data("""
        {"id":"e1000001-0000-4000-8000-000000000001","user_id":null,"name":"Bench Press","type":"strength",
         "related_links":null}
        """.utf8)
        #expect(try JSONDecoder().decode(RemoteExerciseRow.self, from: json).relatedLinks == nil)
    }

    private func encoded(_ row: some Encodable) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
    }

    private func roundTrip<Row: RemoteRow>(_ row: Row) throws -> Row {
        try JSONDecoder().decode(Row.self, from: JSONEncoder().encode(row))
    }
}
