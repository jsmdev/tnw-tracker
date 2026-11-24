import Foundation
import Testing
@testable import TNWTrackerKit

/// The row of a personal link (S10, AC5): what the push sends and what the
/// pull reads. Invented data only.
@Suite("Remote exercise link row coding")
struct RemoteExerciseLinkRowCodingTests {
    @Test("a link sends every column it owns, never the server's timestamps, and reads the server's row back")
    func linkColumns() throws {
        let link = RemoteExerciseLinkRow(
            id: UUID(), userId: UUID(), exerciseId: UUID(), title: "Squat depth",
            url: "https://video.example.test/watch?v=aaa111", source: "video.example.test", position: 2,
            updatedAt: "2026-11-24T10:00:00.123456+00:00"
        )

        let data = try JSONEncoder().encode(link)
        let columns = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(columns.keys) == ["id", "user_id", "exercise_id", "title", "url", "source", "position"])
        #expect(columns["id"] as? String == link.id.uuidString)
        #expect(columns["user_id"] as? String == link.userId.uuidString)
        #expect(columns["exercise_id"] as? String == link.exerciseId.uuidString)
        #expect(columns["title"] as? String == "Squat depth")
        #expect(columns["url"] as? String == "https://video.example.test/watch?v=aaa111")
        #expect(columns["source"] as? String == "video.example.test")
        #expect(columns["position"] as? Int == 2)

        let server = Data("""
        {"id":"\(link.id.uuidString.lowercased())","user_id":"\(link.userId.uuidString.lowercased())",
         "exercise_id":"\(link.exerciseId.uuidString.lowercased())","title":"Squat depth",
         "url":"https://video.example.test/watch?v=aaa111","source":"video.example.test","position":2,
         "created_at":"2026-11-24T09:00:00+00:00","updated_at":"2026-11-24T10:00:00.123456+00:00"}
        """.utf8)
        #expect(try JSONDecoder().decode(RemoteExerciseLinkRow.self, from: server) == link)
        #expect(RemoteTable.exerciseLinks.rawValue == "exercise_links")
        #expect(RemoteTable.exerciseLinks.keyColumn == "id")
        #expect(RemoteTable.exerciseLinks.conflictTarget == "id")
        #expect(RemoteTable.exerciseLinks.parentColumn == nil)
    }

    @Test("a tombstone of exercise_links names the links table")
    func tombstoneNamesLinks() {
        let tombstone = RemoteTombstoneRow(userId: UUID(), tableName: "exercise_links", rowId: UUID())
        #expect(tombstone.deletedTable == .exerciseLinks)
    }
}
