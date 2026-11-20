import Foundation
import Testing
@testable import TNWTracker
@testable import TNWTrackerKit

// MARK: - Rest settings (T3, AC3.1–AC3.6)

/// "Descanso entre series" per exercise and "Descanso al cambiar de ejercicio"
/// in Settings, driven through the coordinator's public interface.
@Suite("Rest settings", .serialized)
@MainActor
struct RestSettingsTests {
    let fx: TrainingFixtures

    init() throws {
        fx = try TrainingFixtures()
    }

    private func makeCoordinator(changeExerciseRest: Int? = 120) -> ActiveWorkoutCoordinator {
        ActiveWorkoutCoordinator(
            sessions: fx.sessions,
            routines: fx.routines,
            exerciseSettings: fx.store.exerciseSettings,
            changeExerciseRest: { changeExerciseRest },
            requestSync: {},
            timerService: RestTimerService(),
            liveActivity: LiveActivitySpy(),
            now: { TrainingFixtures.t0 }
        )
    }

    /// Duration and type of the rest the coordinator started, if any.
    private func rest(_ coordinator: ActiveWorkoutCoordinator) -> (type: TimerType, seconds: Int)? {
        coordinator.timerState.map { ($0.type, Int($0.endsAt.timeIntervalSince($0.startedAt).rounded())) }
    }

    private func logSet(_ coordinator: ActiveWorkoutCoordinator) async throws {
        try await coordinator.recordSet(reps: 8, weight: .kg(20), rir: 2)
    }

    // MARK: AC3.1

    @Test("AC3.1 without a saved setting, the rest between sets is the routine item's restSeconds")
    func routineRestWhenNoSetting() async throws {
        let routine = Routine(name: "Upper", items: [
            RoutineItem(order: 1, exerciseId: fx.press.id, targetSets: 3, restSeconds: 75),
            RoutineItem(order: 2, exerciseId: fx.squat.id, targetSets: 3)
        ])
        try fx.routines.save(routine)
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        try await logSet(coordinator)

        #expect(coordinator.phase == .restingBetweenSets)
        #expect(rest(coordinator)?.type == .betweenSets)
        #expect(rest(coordinator)?.seconds == 75)
        #expect(coordinator.restSetting(for: fx.squat.id) == ExerciseSetting(exerciseId: fx.squat.id, restSeconds: 90))
        await coordinator.skipTimer()
    }

    @Test("AC3.1 without a saved setting or a routine rest, the rest between sets is 90 s")
    func defaultRestWhenNothingSet() async throws {
        let routine = Routine(name: "Upper", items: [
            RoutineItem(order: 1, exerciseId: fx.press.id, targetSets: 3)
        ])
        try fx.routines.save(routine)
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)

        try await logSet(coordinator)

        #expect(rest(coordinator)?.type == .betweenSets)
        #expect(rest(coordinator)?.seconds == RestPolicy.defaultBetweenSetsSeconds)
        #expect(RestPolicy.defaultBetweenSetsSeconds == 90)
        await coordinator.skipTimer()
    }

    // MARK: AC3.2

    @Test("AC3.2 a rest changed during a session is saved and used in a later session, routine or free")
    func settingSavedForLaterSessions() async throws {
        let routine = try fx.makeRoutine() // squat: 3 sets, 90 s
        let first = makeCoordinator()
        try await first.start(routineId: routine.id)
        var setting = first.restSetting(for: fx.squat.id)
        setting.restSeconds = 45
        try first.saveRestSetting(setting)
        try await logSet(first)
        #expect(rest(first)?.seconds == 45, "editable during the session")
        await first.skipTimer()
        try await first.finish()

        // Read back from the store, not from the coordinator.
        #expect(try fx.store.exerciseSettings.setting(exerciseId: fx.squat.id)
            == ExerciseSetting(exerciseId: fx.squat.id, restEnabled: true, restSeconds: 45))

        let second = makeCoordinator()
        try await second.start(routineId: routine.id)
        try await logSet(second)
        #expect(rest(second)?.type == .betweenSets)
        #expect(rest(second)?.seconds == 45)
        await second.skipTimer()
        try await second.finish()

        let free = makeCoordinator()
        try await free.startAdHoc(name: "Free")
        #expect(free.restSetting(for: fx.squat.id).restSeconds == 45)
    }

    @Test("AC3.2 the repository replaces the setting of an existing exercise and rejects bad input")
    func repositoryRoundTrip() throws {
        let repository = fx.store.exerciseSettings
        #expect(try repository.setting(exerciseId: fx.press.id) == nil)

        try repository.save(ExerciseSetting(exerciseId: fx.press.id, restEnabled: true, restSeconds: 60))
        try repository.save(ExerciseSetting(exerciseId: fx.press.id, restEnabled: false, restSeconds: 105))
        #expect(try repository.setting(exerciseId: fx.press.id)
            == ExerciseSetting(exerciseId: fx.press.id, restEnabled: false, restSeconds: 105))

        #expect(throws: TrainingDataError.notFound) {
            try repository.save(ExerciseSetting(exerciseId: UUID(), restSeconds: 60))
        }
        #expect(throws: TrainingDataError.invalidExercise("rest seconds must not be negative")) {
            try repository.save(ExerciseSetting(exerciseId: fx.press.id, restSeconds: -15))
        }
        #expect(try repository.setting(exerciseId: fx.press.id)?.restSeconds == 105)
    }

    @Test("AC3.2 deleting all training data also deletes the exercises' settings")
    func deleteAllRemovesSettings() throws {
        try fx.store.exerciseSettings.save(ExerciseSetting(exerciseId: fx.press.id, restSeconds: 60))
        try fx.store.deleteAllTrainingData()
        #expect(try fx.store.exerciseSettings.setting(exerciseId: fx.press.id) == nil)
    }

    // MARK: AC3.3

    @Test("AC3.3 with the exercise's rest off no rest starts, and turning it on restores the duration")
    func restOffThenOn() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator()
        try await coordinator.start(routineId: routine.id)
        try coordinator.saveRestSetting(ExerciseSetting(exerciseId: fx.squat.id, restEnabled: true, restSeconds: 75))

        var setting = coordinator.restSetting(for: fx.squat.id)
        setting.restEnabled = false
        try coordinator.saveRestSetting(setting)
        try await logSet(coordinator)

        #expect(coordinator.phase == .active)
        #expect(coordinator.timerState == nil)
        #expect(coordinator.restSetting(for: fx.squat.id).restSeconds == 75, "off keeps the duration")

        setting = coordinator.restSetting(for: fx.squat.id)
        setting.restEnabled = true
        try coordinator.saveRestSetting(setting)
        try await logSet(coordinator)

        #expect(coordinator.phase == .restingBetweenSets)
        #expect(rest(coordinator)?.type == .betweenSets)
        #expect(rest(coordinator)?.seconds == 75)
        await coordinator.skipTimer()
    }

    // MARK: AC3.4

    @Test("AC3.4 after the last working set of a non-last exercise, the change-exercise rest starts")
    func changeExerciseRestAfterLastSet() async throws {
        let routine = try fx.makeRoutine() // squat: 3 sets, then press
        let coordinator = makeCoordinator(changeExerciseRest: 150)
        try await coordinator.start(routineId: routine.id)
        try coordinator.saveRestSetting(ExerciseSetting(exerciseId: fx.squat.id, restSeconds: 45))

        try await coordinator.recordSet(reps: 12, weight: .kg(8), rir: 5, warmup: true)
        for _ in 1 ... 2 {
            try await logSet(coordinator)
            await coordinator.skipTimer()
        }
        try await logSet(coordinator)

        #expect(coordinator.phase == .restingBetweenExercises)
        #expect(rest(coordinator)?.type == .betweenExercises)
        #expect(rest(coordinator)?.seconds == 150, "not the exercise's 45 s")
        await coordinator.skipTimer()
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("AC3.4 with the change-exercise rest off no rest starts and the next exercise follows")
    func changeExerciseRestOff() async throws {
        let routine = try fx.makeRoutine()
        let coordinator = makeCoordinator(changeExerciseRest: nil)
        try await coordinator.start(routineId: routine.id)

        for _ in 1 ... 2 {
            try await logSet(coordinator)
            await coordinator.skipTimer()
        }
        try await logSet(coordinator)

        #expect(coordinator.timerState == nil)
        #expect(coordinator.phase == .active)
        #expect(coordinator.currentExerciseIndex == 1)
        #expect(coordinator.currentEntry?.exerciseId == fx.press.id)
    }

    @Test("AC3.4 the change-exercise rest is on with 120 s by default and off keeps its duration")
    func changeExercisePreferenceDefaults() throws {
        let suite = "rest-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preference = ChangeExerciseRestPreference(defaults: defaults)

        #expect(preference.isEnabled)
        #expect(preference.seconds == 120)
        #expect(preference.restSeconds == 120)

        defaults.set(135, forKey: ChangeExerciseRestPreference.secondsKey)
        defaults.set(false, forKey: ChangeExerciseRestPreference.enabledKey)
        #expect(preference.restSeconds == nil)
        #expect(preference.seconds == 135)

        defaults.set(true, forKey: ChangeExerciseRestPreference.enabledKey)
        #expect(preference.restSeconds == 135)
    }

    // MARK: AC3.5

    @Test("AC3.5 after the last working set of the last exercise no rest starts")
    func noRestAfterLastExercise() async throws {
        let routine = try fx.makeRoutine() // press: 2 sets, last exercise
        let coordinator = makeCoordinator(changeExerciseRest: 120)
        try await coordinator.start(routineId: routine.id)
        try coordinator.saveRestSetting(ExerciseSetting(exerciseId: fx.press.id, restSeconds: 60))
        coordinator.advanceToNextExercise()

        try await logSet(coordinator)
        await coordinator.skipTimer()
        try await logSet(coordinator)

        #expect(coordinator.phase == .finishing)
        #expect(coordinator.timerState == nil)
    }

    // MARK: AC3.6

    @Test("AC3.6 −15 s / +15 s change both timers the same way", arguments: [false, true])
    func adjustBothTimers(lastSet: Bool) async throws {
        let routine = Routine(name: "Two", items: [
            RoutineItem(order: 1, exerciseId: fx.squat.id, targetSets: lastSet ? 1 : 3, restSeconds: 90),
            RoutineItem(order: 2, exerciseId: fx.press.id, targetSets: 2)
        ])
        try fx.routines.save(routine)
        let coordinator = makeCoordinator(changeExerciseRest: 90)
        try await coordinator.start(routineId: routine.id)
        try await logSet(coordinator)
        #expect(rest(coordinator)?.type == (lastSet ? .betweenExercises : .betweenSets))

        await coordinator.adjustTimer(by: RestPolicy.stepSeconds)
        #expect(rest(coordinator)?.seconds == 105)
        await coordinator.adjustTimer(by: -RestPolicy.stepSeconds * 2)
        #expect(rest(coordinator)?.seconds == 75)
        await coordinator.adjustTimer(by: -600)
        #expect(rest(coordinator)?.seconds == 0, "a rest never ends before now")
        await coordinator.skipTimer()
        #expect(coordinator.timerState == nil)
    }
}
