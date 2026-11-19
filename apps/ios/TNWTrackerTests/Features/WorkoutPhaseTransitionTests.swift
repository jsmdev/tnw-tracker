import Foundation
import Testing
@testable import TNWTrackerKit

// MARK: - WorkoutPhaseTransitionTests

//
// Cobertura exhaustiva de WorkoutPhaseTransition.evaluate.
// Función pura sin IO: cero mocks, cero shared state, instantánea.
// Cada test es una invariante del FSM del workout que protegemos
// contra regresiones.

@Suite("WorkoutPhaseTransition")
struct WorkoutPhaseTransitionTests {
    // MARK: - Sin transición

    @Test("warmup set returns nil — no transition fires")
    func warmupReturnsNil() {
        let outcome = WorkoutPhaseTransition.evaluate(
            set: .init(number: 1, isWarmup: true),
            exercise: .init(target: 4, restSeconds: 90, index: 0, total: 3),
            triggerMode: .auto
        )
        #expect(outcome == nil)
    }

    @Test("manual trigger mode returns nil — coordinator must not auto-advance")
    func manualModeReturnsNil() {
        let outcome = WorkoutPhaseTransition.evaluate(
            set: .init(number: 1, isWarmup: false),
            exercise: .init(target: 4, restSeconds: 90, index: 0, total: 3),
            triggerMode: .manual
        )
        #expect(outcome == nil)
    }

    // MARK: - Transición a finishing

    @Test("last set of last exercise transitions to finishing with no timer")
    func lastSetOfLastExerciseFinishes() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 4, isWarmup: false),
                exercise: .init(target: 4, restSeconds: 90, index: 2, total: 3),
                triggerMode: .auto
            )
        )
        #expect(outcome.nextPhase == .finishing)
        #expect(outcome.restTimer == nil)
    }

    // MARK: - Transición a resting between exercises

    @Test("last set of non-last exercise rests between exercises")
    func lastSetOfNonLastExerciseRestsBetweenExercises() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 4, isWarmup: false),
                exercise: .init(target: 4, restSeconds: 120, index: 0, total: 3),
                triggerMode: .auto
            )
        )
        #expect(outcome.nextPhase == .restingBetweenExercises)
        let timer = try #require(outcome.restTimer)
        #expect(timer.type == .betweenExercises)
        #expect(timer.durationSeconds == 120)
    }

    // MARK: - Transición a resting between sets

    @Test("non-last set rests between sets")
    func nonLastSetRestsBetweenSets() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 2, isWarmup: false),
                exercise: .init(target: 4, restSeconds: 90, index: 0, total: 3),
                triggerMode: .auto
            )
        )
        #expect(outcome.nextPhase == .restingBetweenSets)
        let timer = try #require(outcome.restTimer)
        #expect(timer.type == .betweenSets)
        #expect(timer.durationSeconds == 90)
    }

    // MARK: - Edge case: workout de un solo ejercicio

    @Test("single-exercise workout transitions to finishing on last set")
    func singleExerciseWorkoutFinishes() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 3, isWarmup: false),
                exercise: .init(target: 3, restSeconds: 60, index: 0, total: 1),
                triggerMode: .auto
            )
        )
        #expect(outcome.nextPhase == .finishing)
        #expect(outcome.restTimer == nil)
    }

    // MARK: - Edge case: setNumber excede target

    @Test("set beyond target still triggers last-set behavior")
    func setBeyondTargetTreatedAsLast() throws {
        // Defensive: si por alguna razón se registra un set extra,
        // tratarlo como "último set" es más seguro que ignorarlo.
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 5, isWarmup: false),
                exercise: .init(target: 4, restSeconds: 90, index: 0, total: 3),
                triggerMode: .auto
            )
        )
        #expect(outcome.nextPhase == .restingBetweenExercises)
    }

    // MARK: - Rest settings (T3)

    @Test("AC3.4 the last set of a non-last exercise uses the change-exercise rest, not the rest between sets")
    func changeExerciseRestIsUsedAfterLastSet() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 3, isWarmup: false),
                exercise: .init(target: 3, restBetweenSets: 45, restAfterExercise: 120, index: 0, total: 2),
                triggerMode: .auto
            )
        )
        #expect(
            outcome == .init(
                nextPhase: .restingBetweenExercises,
                restTimer: .init(type: .betweenExercises, durationSeconds: 120)
            )
        )
    }

    @Test("AC3.4 with the change-exercise rest off, the last set of a non-last exercise starts no rest")
    func changeExerciseRestOff() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 3, isWarmup: false),
                exercise: .init(target: 3, restBetweenSets: 45, restAfterExercise: nil, index: 0, total: 2),
                triggerMode: .auto
            )
        )
        #expect(outcome == .init(nextPhase: .restingBetweenExercises, restTimer: nil))
    }

    @Test("AC3.3 with the rest between sets off, a non-last set starts no rest and stays active")
    func restBetweenSetsOff() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 1, isWarmup: false),
                exercise: .init(target: 3, restBetweenSets: nil, restAfterExercise: 120, index: 0, total: 2),
                triggerMode: .auto
            )
        )
        #expect(outcome == .init(nextPhase: .active, restTimer: nil))
    }

    @Test("AC3.1 a non-last set uses the rest between sets")
    func restBetweenSetsUsed() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 1, isWarmup: false),
                exercise: .init(target: 3, restBetweenSets: 75, restAfterExercise: 120, index: 0, total: 2),
                triggerMode: .auto
            )
        )
        #expect(
            outcome == .init(nextPhase: .restingBetweenSets, restTimer: .init(type: .betweenSets, durationSeconds: 75))
        )
    }

    @Test("AC3.5 the last set of the last exercise starts no rest, whatever the settings")
    func noRestAfterLastExercise() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                set: .init(number: 2, isWarmup: false),
                exercise: .init(target: 2, restBetweenSets: 60, restAfterExercise: 120, index: 1, total: 2),
                triggerMode: .auto
            )
        )
        #expect(outcome == .init(nextPhase: .finishing, restTimer: nil))
    }
}
