import { z } from "zod";

// weight_unit
export const weightUnitSchema = z.enum(["kg", "lb"]);
export type WeightUnit = z.infer<typeof weightUnitSchema>;

// exercise_category
export const exerciseCategorySchema = z.enum(["Push", "Pull", "Legs", "Core", "Cardio", "Other"]);
export type ExerciseCategory = z.infer<typeof exerciseCategorySchema>;

// video_source
export const videoSourceSchema = z.enum(["youtube", "storage"]);
export type VideoSource = z.infer<typeof videoSourceSchema>;

// workout_status
export const workoutStatusSchema = z.enum(["active", "paused", "completed", "cancelled"]);
export type WorkoutStatus = z.infer<typeof workoutStatusSchema>;

// workout_exercise_status
export const workoutExerciseStatusSchema = z.enum([
  "pending",
  "in_progress",
  "completed",
  "skipped",
]);
export type WorkoutExerciseStatus = z.infer<typeof workoutExerciseStatusSchema>;

// timer_type
export const timerTypeSchema = z.enum(["between_sets", "between_exercises"]);
export type TimerType = z.infer<typeof timerTypeSchema>;

// pr_record_type
export const prRecordTypeSchema = z.enum(["max_weight", "max_reps", "max_volume"]);
export type PrRecordType = z.infer<typeof prRecordTypeSchema>;

// timer_trigger_mode
export const timerTriggerModeSchema = z.enum(["auto", "manual"]);
export type TimerTriggerMode = z.infer<typeof timerTriggerModeSchema>;
