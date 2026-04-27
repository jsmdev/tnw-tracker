import { z } from "zod";
import {
  workoutStatusSchema,
  workoutExerciseStatusSchema,
  timerTypeSchema,
  prRecordTypeSchema,
  weightUnitSchema,
} from "./enums";

// Workout — read
export const workoutSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  session_id: z.string().uuid().nullable(),
  name: z.string().min(1),
  status: workoutStatusSchema,
  started_at: z.string().datetime().nullable(),
  finished_at: z.string().datetime().nullable(),
  notes: z.string().nullable(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type Workout = z.infer<typeof workoutSchema>;

// Workout — insert
export const createWorkoutSchema = z.object({
  user_id: z.string().uuid(),
  session_id: z.string().uuid().nullable().optional(),
  name: z.string().min(1),
  status: workoutStatusSchema.optional(),
  started_at: z.string().datetime().nullable().optional(),
  finished_at: z.string().datetime().nullable().optional(),
  notes: z.string().nullable().optional(),
});
export type CreateWorkout = z.infer<typeof createWorkoutSchema>;

// WorkoutExercise — read
export const workoutExerciseSchema = z.object({
  id: z.string().uuid(),
  workout_id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  session_exercise_id: z.string().uuid().nullable(),
  order_index: z.number().int().min(0),
  status: workoutExerciseStatusSchema,
  notes: z.string().nullable(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type WorkoutExercise = z.infer<typeof workoutExerciseSchema>;

// WorkoutExercise — insert
export const createWorkoutExerciseSchema = z.object({
  workout_id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  session_exercise_id: z.string().uuid().nullable().optional(),
  order_index: z.number().int().min(0),
  status: workoutExerciseStatusSchema.optional(),
  notes: z.string().nullable().optional(),
});
export type CreateWorkoutExercise = z.infer<typeof createWorkoutExerciseSchema>;

// ExerciseSet — read
export const exerciseSetSchema = z.object({
  id: z.string().uuid(),
  workout_exercise_id: z.string().uuid(),
  set_number: z.number().int().positive(),
  weight: z.number().min(0).nullable(),
  weight_unit: weightUnitSchema,
  reps: z.number().int().positive().nullable(),
  rpe: z.number().min(1).max(10).nullable(),
  completed: z.boolean(),
  notes: z.string().nullable(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type ExerciseSet = z.infer<typeof exerciseSetSchema>;

// ExerciseSet — insert
export const createExerciseSetSchema = z.object({
  workout_exercise_id: z.string().uuid(),
  set_number: z.number().int().positive(),
  weight: z.number().min(0).nullable().optional(),
  weight_unit: weightUnitSchema.optional(),
  reps: z.number().int().positive().nullable().optional(),
  rpe: z.number().min(1).max(10).nullable().optional(),
  completed: z.boolean().optional(),
  notes: z.string().nullable().optional(),
});
export type CreateExerciseSet = z.infer<typeof createExerciseSetSchema>;

// ExerciseSet — update
export const updateExerciseSetSchema = createExerciseSetSchema
  .partial()
  .omit({ workout_exercise_id: true });
export type UpdateExerciseSet = z.infer<typeof updateExerciseSetSchema>;

// RestTimer — read
export const restTimerSchema = z.object({
  id: z.string().uuid(),
  workout_exercise_id: z.string().uuid(),
  timer_type: timerTypeSchema,
  duration_seconds: z.number().int().positive(),
  started_at: z.string().datetime().nullable(),
  finished_at: z.string().datetime().nullable(),
  created_at: z.string().datetime().optional(),
});
export type RestTimer = z.infer<typeof restTimerSchema>;

// RestTimer — insert
export const createRestTimerSchema = z.object({
  workout_exercise_id: z.string().uuid(),
  timer_type: timerTypeSchema,
  duration_seconds: z.number().int().positive(),
  started_at: z.string().datetime().nullable().optional(),
  finished_at: z.string().datetime().nullable().optional(),
});
export type CreateRestTimer = z.infer<typeof createRestTimerSchema>;

// PersonalRecord — read only (PRs are computed/inserted by backend logic)
export const personalRecordSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  record_type: prRecordTypeSchema,
  value: z.number().positive(),
  weight_unit: weightUnitSchema.nullable(),
  achieved_at: z.string().datetime(),
  workout_id: z.string().uuid().nullable(),
  set_id: z.string().uuid().nullable(),
  created_at: z.string().datetime().optional(),
});
export type PersonalRecord = z.infer<typeof personalRecordSchema>;
