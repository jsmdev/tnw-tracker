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
            setNumber: 1,
            target: 4,
            restSeconds: 90,
            currentExerciseIndex: 0,
            totalExercises: 3,
            isWarmup: true,
            triggerMode: .auto
        )
        #expect(outcome == nil)
    }

    @Test("manual trigger mode returns nil — coordinator must not auto-advance")
    func manualModeReturnsNil() {
        let outcome = WorkoutPhaseTransition.evaluate(
            setNumber: 1,
            target: 4,
            restSeconds: 90,
            currentExerciseIndex: 0,
            totalExercises: 3,
            isWarmup: false,
            triggerMode: .manual
        )
        #expect(outcome == nil)
    }

    // MARK: - Transición a finishing

    @Test("last set of last exercise transitions to finishing with no timer")
    func lastSetOfLastExerciseFinishes() throws {
        let outcome = try #require(
            WorkoutPhaseTransition.evaluate(
                setNumber: 4,
                target: 4,
                restSeconds: 90,
                currentExerciseIndex: 2,
                totalExercises: 3,
                isWarmup: false,
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
                setNumber: 4,
                target: 4,
                restSeconds: 120,
                currentExerciseIndex: 0,
                totalExercises: 3,
                isWarmup: false,
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
                setNumber: 2,
                target: 4,
                restSeconds: 90,
                currentExerciseIndex: 0,
                totalExercises: 3,
                isWarmup: false,
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
                setNumber: 3,
                target: 3,
                restSeconds: 60,
                currentExerciseIndex: 0,
                totalExercises: 1,
                isWarmup: false,
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
                setNumber: 5,
                target: 4,
                restSeconds: 90,
                currentExerciseIndex: 0,
                totalExercises: 3,
                isWarmup: false,
                triggerMode: .auto
            )
        )
        #expect(outcome.nextPhase == .restingBetweenExercises)
    }
}
