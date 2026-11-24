import Foundation

// Rows of the server tables (supabase/migrations/20261117050646_training_data_schema.sql),
// as the sync sends and receives them. Column names follow docs/database-schema.md.
//
// Encoding writes every column the client owns, `null` included: an upsert only
// updates the columns present in the request, so an omitted `nil` would never
// clear a value on the server. `created_at` and `updated_at` belong to the server
// and are never sent; `updatedAt` is read back as the exact text the server
// returned, because it is half of the pull cursor and a `Date` would lose
// microseconds.

/// A server table the sync reads with a cursor.
public enum RemoteTable: String, Sendable, CaseIterable {
    case exercises
    case exerciseMuscleGroups = "exercise_muscle_groups"
    case routines
    case routineItems = "routine_items"
    case sessions
    case entries
    case sets
    /// Keyed by `exercise_id` for its owner (`RemoteExerciseSettingRow`).
    case exerciseSettings = "exercise_settings"
    /// Personal related links of exercises (`RemoteExerciseLinkRow`).
    case exerciseLinks = "exercise_links"
    /// Rows the server deleted from the tables above (`RemoteTombstoneRow`).
    case tombstones
}

/// A row of a table that carries `updated_at`, identified for its owner by
/// `id`: the table's `keyColumn`, which is `id` except for `exercise_settings`.
public protocol RemoteRow: Codable, Sendable, Equatable, Identifiable where ID == UUID {
    static var table: RemoteTable { get }
    /// `updated_at` as the server wrote it; `nil` on a row not yet stored.
    var updatedAt: String? { get set }
}

/// Position in a table's change feed: the last row read, ordered by
/// (`updated_at`, `id`). Both values come from the server, never from the
/// device clock.
public struct RemoteCursor: Hashable, Codable, Sendable {
    public var updatedAt: String
    public var id: UUID

    public init(updatedAt: String, id: UUID) {
        self.updatedAt = updatedAt
        self.id = id
    }
}

/// One page of changed rows, in cursor order.
public struct RemotePage<Row: RemoteRow>: Sendable, Equatable {
    public var rows: [Row]
    /// Cursor of the last row, to ask for the next page; `nil` when the page is empty.
    public var next: RemoteCursor?
    /// `true` when the page is full, so more rows may follow.
    public var mayHaveMore: Bool

    public init(rows: [Row], limit: Int) {
        self.rows = rows
        next = rows.last.flatMap { row in row.updatedAt.map { RemoteCursor(updatedAt: $0, id: row.id) } }
        mayHaveMore = rows.count >= limit
    }
}

// MARK: - sessions

public struct RemoteSessionRow: RemoteRow {
    public static let table = RemoteTable.sessions

    public var id: UUID
    public var userId: UUID
    public var routineId: UUID?
    public var name: String?
    public var notes: String?
    public var startedAt: Date?
    public var completedAt: Date
    /// IANA identifier, for example `Europe/Madrid`.
    public var timeZone: String
    public var durationSeconds: Int?
    public var externalRef: ExternalRef?
    public var updatedAt: String?

    public init(
        id: UUID,
        userId: UUID,
        routineId: UUID? = nil,
        name: String? = nil,
        notes: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date,
        timeZone: String,
        durationSeconds: Int? = nil,
        externalRef: ExternalRef? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.routineId = routineId
        self.name = name
        self.notes = notes
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.timeZone = timeZone
        self.durationSeconds = durationSeconds
        self.externalRef = externalRef
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case routineId = "routine_id"
        case name, notes
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case timeZone = "time_zone"
        case durationSeconds = "duration_seconds"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        userId = try values.decode(UUID.self, forKey: .userId)
        routineId = try values.decodeIfPresent(UUID.self, forKey: .routineId)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try values.decode(Date.self, forKey: .completedAt)
        timeZone = try values.decode(String.self, forKey: .timeZone)
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds)
        externalRef = try ExternalRefColumns.decode(from: decoder)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(routineId, forKey: .routineId)
        try values.encode(name, forKey: .name)
        try values.encode(notes, forKey: .notes)
        try values.encode(startedAt, forKey: .startedAt)
        try values.encode(completedAt, forKey: .completedAt)
        try values.encode(timeZone, forKey: .timeZone)
        try values.encode(durationSeconds, forKey: .durationSeconds)
        try ExternalRefColumns.encode(externalRef, to: encoder)
    }
}

// MARK: - entries

public struct RemoteEntryRow: RemoteRow {
    public static let table = RemoteTable.entries

    public var id: UUID
    public var userId: UUID
    public var sessionId: UUID
    public var position: Int
    public var exerciseId: UUID
    public var status: EntryStatus
    public var replacedExerciseId: UUID?
    public var completedAt: Date?
    public var notes: String?
    public var reconciliationKeep: SetSource?
    public var reconciliationDecidedBy: ReconciliationDecider?
    public var reconciliationDecidedAt: Date?
    public var externalRef: ExternalRef?
    public var updatedAt: String?

    public init(
        id: UUID,
        userId: UUID,
        sessionId: UUID,
        position: Int,
        exerciseId: UUID,
        status: EntryStatus,
        replacedExerciseId: UUID? = nil,
        completedAt: Date? = nil,
        notes: String? = nil,
        reconciliationKeep: SetSource? = nil,
        reconciliationDecidedBy: ReconciliationDecider? = nil,
        reconciliationDecidedAt: Date? = nil,
        externalRef: ExternalRef? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.sessionId = sessionId
        self.position = position
        self.exerciseId = exerciseId
        self.status = status
        self.replacedExerciseId = replacedExerciseId
        self.completedAt = completedAt
        self.notes = notes
        self.reconciliationKeep = reconciliationKeep
        self.reconciliationDecidedBy = reconciliationDecidedBy
        self.reconciliationDecidedAt = reconciliationDecidedAt
        self.externalRef = externalRef
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sessionId = "session_id"
        case position
        case exerciseId = "exercise_id"
        case status
        case replacedExerciseId = "replaced_exercise_id"
        case completedAt = "completed_at"
        case notes
        case reconciliationKeep = "reconciliation_keep"
        case reconciliationDecidedBy = "reconciliation_decided_by"
        case reconciliationDecidedAt = "reconciliation_decided_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        userId = try values.decode(UUID.self, forKey: .userId)
        sessionId = try values.decode(UUID.self, forKey: .sessionId)
        position = try values.decode(Int.self, forKey: .position)
        exerciseId = try values.decode(UUID.self, forKey: .exerciseId)
        status = try values.decode(EntryStatus.self, forKey: .status)
        replacedExerciseId = try values.decodeIfPresent(UUID.self, forKey: .replacedExerciseId)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        reconciliationKeep = try values.decodeIfPresent(SetSource.self, forKey: .reconciliationKeep)
        reconciliationDecidedBy = try values.decodeIfPresent(
            ReconciliationDecider.self, forKey: .reconciliationDecidedBy
        )
        reconciliationDecidedAt = try values.decodeIfPresent(Date.self, forKey: .reconciliationDecidedAt)
        externalRef = try ExternalRefColumns.decode(from: decoder)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(sessionId, forKey: .sessionId)
        try values.encode(position, forKey: .position)
        try values.encode(exerciseId, forKey: .exerciseId)
        try values.encode(status, forKey: .status)
        try values.encode(replacedExerciseId, forKey: .replacedExerciseId)
        try values.encode(completedAt, forKey: .completedAt)
        try values.encode(notes, forKey: .notes)
        try values.encode(reconciliationKeep, forKey: .reconciliationKeep)
        try values.encode(reconciliationDecidedBy, forKey: .reconciliationDecidedBy)
        try values.encode(reconciliationDecidedAt, forKey: .reconciliationDecidedAt)
        try ExternalRefColumns.encode(externalRef, to: encoder)
    }
}

// MARK: - sets

public struct RemoteSetRow: RemoteRow {
    public static let table = RemoteTable.sets

    public var id: UUID
    public var userId: UUID
    public var entryId: UUID
    /// Position among the sets of the same source in the entry, from 1.
    public var position: Int
    public var source: SetSource
    public var reps: Int?
    public var weight: Weight?
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var rir: Int?
    public var restSeconds: Int?
    public var completedAt: Date?
    public var superseded: Bool
    public var warmup: Bool
    public var externalRef: ExternalRef?
    public var updatedAt: String?

    public init(
        id: UUID,
        userId: UUID,
        entryId: UUID,
        position: Int,
        source: SetSource,
        reps: Int? = nil,
        weight: Weight? = nil,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        rir: Int? = nil,
        restSeconds: Int? = nil,
        completedAt: Date? = nil,
        superseded: Bool = false,
        warmup: Bool = false,
        externalRef: ExternalRef? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.entryId = entryId
        self.position = position
        self.source = source
        self.reps = reps
        self.weight = weight
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.rir = rir
        self.restSeconds = restSeconds
        self.completedAt = completedAt
        self.superseded = superseded
        self.warmup = warmup
        self.externalRef = externalRef
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case entryId = "entry_id"
        case position, source, reps, weight
        case weightUnit = "weight_unit"
        case durationSeconds = "duration_seconds"
        case distanceMeters = "distance_meters"
        case rir
        case restSeconds = "rest_seconds"
        case completedAt = "completed_at"
        case superseded, warmup
        case updatedAt = "updated_at"
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        userId = try values.decode(UUID.self, forKey: .userId)
        entryId = try values.decode(UUID.self, forKey: .entryId)
        position = try values.decode(Int.self, forKey: .position)
        source = try values.decode(SetSource.self, forKey: .source)
        reps = try values.decodeIfPresent(Int.self, forKey: .reps)
        if let value = try values.decodeIfPresent(Double.self, forKey: .weight) {
            weight = try Weight(value: value, unit: values.decode(WeightUnit.self, forKey: .weightUnit))
        } else {
            weight = nil
        }
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds)
        distanceMeters = try values.decodeIfPresent(Double.self, forKey: .distanceMeters)
        rir = try values.decodeIfPresent(Int.self, forKey: .rir)
        restSeconds = try values.decodeIfPresent(Int.self, forKey: .restSeconds)
        completedAt = try values.decodeIfPresent(Date.self, forKey: .completedAt)
        superseded = try values.decode(Bool.self, forKey: .superseded)
        warmup = try values.decode(Bool.self, forKey: .warmup)
        externalRef = try ExternalRefColumns.decode(from: decoder)
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(userId, forKey: .userId)
        try values.encode(entryId, forKey: .entryId)
        try values.encode(position, forKey: .position)
        try values.encode(source, forKey: .source)
        try values.encode(reps, forKey: .reps)
        try values.encode(weight?.value, forKey: .weight)
        try values.encode(weight?.unit, forKey: .weightUnit)
        try values.encode(durationSeconds, forKey: .durationSeconds)
        try values.encode(distanceMeters, forKey: .distanceMeters)
        try values.encode(rir, forKey: .rir)
        try values.encode(restSeconds, forKey: .restSeconds)
        try values.encode(completedAt, forKey: .completedAt)
        try values.encode(superseded, forKey: .superseded)
        try values.encode(warmup, forKey: .warmup)
        try ExternalRefColumns.encode(externalRef, to: encoder)
    }
}

// MARK: - externalRef columns

/// `externalRef` is stored as two columns, `external_provider` and `external_id`.
enum ExternalRefColumns: String, CodingKey {
    case provider = "external_provider"
    case id = "external_id"

    static func decode(from decoder: any Decoder) throws -> ExternalRef? {
        let values = try decoder.container(keyedBy: Self.self)
        guard
            let provider = try values.decodeIfPresent(String.self, forKey: .provider),
            let id = try values.decodeIfPresent(String.self, forKey: .id)
        else { return nil }
        return ExternalRef(provider: provider, id: id)
    }

    static func encode(_ ref: ExternalRef?, to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Self.self)
        try values.encode(ref?.provider, forKey: .provider)
        try values.encode(ref?.id, forKey: .id)
    }
}
