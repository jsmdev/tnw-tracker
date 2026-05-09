import Foundation
import Testing

@Suite("Iso8601 format")
struct Iso8601FormatTests {
    @Test func equivalenceForFixedDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = ISO8601DateFormatter().string(from: date)
        let modern = date.ISO8601Format()
        #expect(modern == legacy)
    }

    @Test func utcRepresentation() {
        let epoch = Date(timeIntervalSince1970: 0)
        let result = epoch.ISO8601Format()
        #expect(result == "1970-01-01T00:00:00Z")
    }

    @Test func roundTrip() throws {
        let now = Date()
        let s = now.ISO8601Format()
        let parsed = try Date(s, strategy: .iso8601)
        let diff = abs(now.timeIntervalSince(parsed))
        #expect(diff < 1.0)
    }
}
