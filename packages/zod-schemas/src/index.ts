/**
 * @tnw/zod-schemas
 *
 * Shared Zod validation schemas used across the monorepo.
 * Import from here instead of defining schemas in each app.
 *
 * @example
 * import { exerciseSchema, createWorkoutSchema } from "@tnw/zod-schemas";
 */

export { z } from "zod";

// Enums
export {
  weightUnitSchema,
  exerciseCategorySchema,
  videoSourceSchema,
  workoutStatusSchema,
  workoutExerciseStatusSchema,
  timerTypeSchema,
  prRecordTypeSchema,
  timerTriggerModeSchema,
} from "./enums";
export type {
  WeightUnit,
  ExerciseCategory,
  VideoSource,
  WorkoutStatus,
  WorkoutExerciseStatus,
  TimerType,
  PrRecordType,
  TimerTriggerMode,
} from "./enums";

// Exercise
export {
  exerciseSchema,
  createExerciseSchema,
  updateExerciseSchema,
  exerciseVideoSchema,
  createExerciseVideoSchema,
} from "./exercise";
export type {
  Exercise,
  CreateExercise,
  UpdateExercise,
  ExerciseVideo,
  CreateExerciseVideo,
} from "./exercise";

// Plan
export {
  planSchema,
  createPlanSchema,
  updatePlanSchema,
  planRoutineSchema,
  createPlanRoutineSchema,
} from "./plan";
export type { Plan, CreatePlan, UpdatePlan, PlanRoutine, CreatePlanRoutine } from "./plan";

// Routine
export {
  routineSchema,
  createRoutineSchema,
  updateRoutineSchema,
  routineSessionSchema,
  createRoutineSessionSchema,
} from "./routine";
export type {
  Routine,
  CreateRoutine,
  UpdateRoutine,
  RoutineSession,
  CreateRoutineSession,
} from "./routine";

// Session
export {
  sessionSchema,
  createSessionSchema,
  updateSessionSchema,
  sessionExerciseSchema,
  createSessionExerciseSchema,
  updateSessionExerciseSchema,
  reorderSchema,
} from "./session";
export type {
  Session,
  CreateSession,
  UpdateSession,
  SessionExercise,
  CreateSessionExercise,
  UpdateSessionExercise,
  ReorderItem,
} from "./session";

// Workout
export {
  workoutSchema,
  createWorkoutSchema,
  workoutExerciseSchema,
  createWorkoutExerciseSchema,
  exerciseSetSchema,
  createExerciseSetSchema,
  updateExerciseSetSchema,
  restTimerSchema,
  createRestTimerSchema,
  personalRecordSchema,
} from "./workout";
export type {
  Workout,
  CreateWorkout,
  WorkoutExercise,
  CreateWorkoutExercise,
  ExerciseSet,
  CreateExerciseSet,
  UpdateExerciseSet,
  RestTimer,
  CreateRestTimer,
  PersonalRecord,
} from "./workout";

// Settings
export { userSettingsSchema, updateUserSettingsSchema } from "./settings";
export type { UserSettings, UpdateUserSettings } from "./settings";
