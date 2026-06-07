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
}
