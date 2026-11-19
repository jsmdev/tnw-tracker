import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

@Suite("WorkoutSummaryBuilder")
struct WorkoutSummaryBuilderTests {
    let exerciseId = UUID()
    let start = Date(timeIntervalSince1970: 1_898_845_200)

    private func set(
        _ reps: Int,
        _ kg: Double,
        order: Int,
        source: SetSource = .manual,
        superseded: Bool = false,
        warmup: Bool = false
    ) -> ExerciseSet {
        ExerciseSet(
            order: order,
            source: source,
            values: SetValues(reps: reps, weight: .kg(kg)),
            superseded: superseded,
            warmup: warmup
        )
    }

    private func session(_ entries: [SessionEntry], duration: Int? = 3720) -> TrainingSession {
        TrainingSession(
            name: "Full Body A", startedAt: start, completedAt: start.addingTimeInterval(4000),
            timeZone: "Europe/Madrid", durationSeconds: duration, entries: entries
        )
    }

    private func entry(_ sets: [ExerciseSet], status: EntryStatus = .done) -> SessionEntry {
        SessionEntry(exerciseId: exerciseId, order: 1, status: status, sets: sets)
    }

    @Test("a PR is detected when the exercise beats its previous best weight")
    func prDetected() {
        let summary = WorkoutSummaryBuilder.build(
            from: session([entry([set(5, 100, order: 1)])]),
            exerciseNames: [exerciseId: "Bench Press"],
            previousBests: [exerciseId: 80]
        )
        #expect(summary.personalRecords.count == 1)
        #expect(summary.personalRecords.first?.exerciseName == "Bench Press")
        #expect(summary.personalRecords.first?.newValue == 100)
    }

    @Test("no PR when the exercise does not beat its previous best")
    func noPR() {
        let summary = WorkoutSummaryBuilder.build(
            from: session([entry([set(5, 70, order: 1)])]),
            exerciseNames: [:],
            previousBests: [exerciseId: 80]
        )
        #expect(summary.personalRecords.isEmpty)
    }

    @Test("a PR is detected when there is no previous best")
    func prWithoutHistory() {
        let summary = WorkoutSummaryBuilder.build(
            from: session([entry([set(5, 60, order: 1)])]), exerciseNames: [:], previousBests: [:]
        )
        #expect(summary.personalRecords.count == 1)
    }

    @Test("total volume sums weight × reps over counted sets only")
    func volumeCountsOnlyCountedSets() {
        let reconciled = entry([
            set(10, 50, order: 1, superseded: true),
            set(10, 40, order: 1, source: .imported),
            set(8, 40, order: 2, source: .imported)
        ])
        var removed = entry([set(10, 100, order: 1)], status: .removed)
        removed.order = 2
        let summary = WorkoutSummaryBuilder.build(
            from: session([reconciled, removed]), exerciseNames: [:], previousBests: [exerciseId: 999]
        )
        let expected: Double = 10 * 40 + 8 * 40
        #expect(summary.totalVolumeKg == expected)
        #expect(summary.exerciseRows.count == 1)
        #expect(summary.exerciseRows.first?.setCount == 2)
    }

    @Test("a superseded set never counts as a PR")
    func supersededNeverPR() {
        let summary = WorkoutSummaryBuilder.build(
            from: session([entry([set(5, 200, order: 1, superseded: true), set(5, 50, order: 1, source: .imported)])]),
            exerciseNames: [:], previousBests: [exerciseId: 100]
        )
        #expect(summary.personalRecords.isEmpty)
    }

    @Test("warm-up sets count for neither volume, set count nor PRs")
    func warmupDoesNotCount() {
        let summary = WorkoutSummaryBuilder.build(
            from: session([entry([set(10, 150, order: 1, warmup: true), set(5, 60, order: 2)])]),
            exerciseNames: [:], previousBests: [exerciseId: 100]
        )
        #expect(summary.totalVolumeKg == 5 * 60)
        #expect(summary.exerciseRows.first?.setCount == 1)
        #expect(summary.personalRecords.isEmpty, "the 150 kg warm-up set is not a PR")
    }

    @Test("duration prefers the stored training time and falls back to start–end")
    func duration() {
        let stored = WorkoutSummaryBuilder.build(from: session([]), exerciseNames: [:], previousBests: [:])
        #expect(stored.durationSeconds == 3720)
        let fallback = WorkoutSummaryBuilder.build(
            from: session([], duration: nil),
            exerciseNames: [:],
            previousBests: [:]
        )
        #expect(fallback.durationSeconds == 4000)
    }

    @Test("Duration FormatStyle formats correctly with es-ES locale")
    func durationFormatES() {
        let summary = WorkoutSummaryBuilder.build(from: session([]), exerciseNames: [:], previousBests: [:])
        let formatted = Duration.seconds(summary.durationSeconds)
            .formatted(.time(pattern: .hourMinuteSecond).locale(Locale(identifier: "es-ES")))
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("1"))
        #expect(formatted.contains("02"))
    }

    @Test("Duration FormatStyle under one hour uses minuteSecond pattern")
    func durationFormatUnderHour() {
        let formatted = Duration.seconds(45 * 60 + 30)
            .formatted(.time(pattern: .minuteSecond).locale(Locale(identifier: "es-ES")))
        #expect(formatted.contains("45"))
        #expect(formatted.contains("30"))
    }

    @Test("exercise rows include name and counted set count, for done entries only")
    func exerciseRows() {
        let skipped = SessionEntry(exerciseId: UUID(), order: 2, status: .skipped)
        let summary = WorkoutSummaryBuilder.build(
            from: session([entry((1 ... 4).map { set(8, 60, order: $0) }), skipped]),
            exerciseNames: [exerciseId: "Overhead Press"], previousBests: [:]
        )
        #expect(summary.exerciseRows.count == 1)
        #expect(summary.exerciseRows.first?.exerciseName == "Overhead Press")
        #expect(summary.exerciseRows.first?.setCount == 4)
        #expect(summary.workoutName == "Full Body A")
    }
}
