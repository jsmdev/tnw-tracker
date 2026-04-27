import { z } from "zod";
import { exerciseCategorySchema, videoSourceSchema } from "./enums";

// ExerciseVideo — read
export const exerciseVideoSchema = z.object({
  id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  source: videoSourceSchema,
  url: z.string().url(),
  created_at: z.string().datetime().optional(),
});
export type ExerciseVideo = z.infer<typeof exerciseVideoSchema>;

// ExerciseVideo — insert
export const createExerciseVideoSchema = z.object({
  exercise_id: z.string().uuid(),
  source: videoSourceSchema,
  url: z.string().url(),
});
export type CreateExerciseVideo = z.infer<typeof createExerciseVideoSchema>;

// Exercise — read
export const exerciseSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid().nullable(),
  name: z.string().min(1),
  category: exerciseCategorySchema,
  muscle_groups: z.array(z.string()),
  description: z.string().nullable(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type Exercise = z.infer<typeof exerciseSchema>;

// Exercise — insert
export const createExerciseSchema = z.object({
  user_id: z.string().uuid().nullable().optional(),
  name: z.string().min(1),
  category: exerciseCategorySchema,
  muscle_groups: z.array(z.string()).default([]),
  description: z.string().nullable().optional(),
});
export type CreateExercise = z.infer<typeof createExerciseSchema>;

// Exercise — update (all fields optional except caller provides id separately)
export const updateExerciseSchema = createExerciseSchema.partial();
export type UpdateExercise = z.infer<typeof updateExerciseSchema>;
