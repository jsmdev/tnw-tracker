import { z } from "zod";

// Session — read
export const sessionSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type Session = z.infer<typeof sessionSchema>;

// Session — insert
export const createSessionSchema = z.object({
  user_id: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable().optional(),
  rest_between_exercises_seconds: z.number().int().min(0).default(60),
});
export type CreateSession = z.infer<typeof createSessionSchema>;

// Session — update
export const updateSessionSchema = createSessionSchema.partial().omit({ user_id: true });
export type UpdateSession = z.infer<typeof updateSessionSchema>;

// SessionExercise — read
export const sessionExerciseSchema = z.object({
  id: z.string().uuid(),
  session_id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  order_index: z.number().int().min(0),
  target_sets: z.number().int().positive().nullable(),
  target_reps: z.number().int().positive().nullable(),
  rest_seconds: z.number().int().min(0).nullable(),
  notes: z.string().nullable(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type SessionExercise = z.infer<typeof sessionExerciseSchema>;

// SessionExercise — insert
export const createSessionExerciseSchema = z.object({
  session_id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  order_index: z.number().int().min(0),
  target_sets: z.number().int().positive().nullable().optional(),
  target_reps: z.number().int().positive().nullable().optional(),
  rest_seconds: z.number().int().min(0).nullable().optional(),
  notes: z.string().nullable().optional(),
});
export type CreateSessionExercise = z.infer<typeof createSessionExerciseSchema>;

// SessionExercise — update
export const updateSessionExerciseSchema = createSessionExerciseSchema
  .partial()
  .omit({ session_id: true, exercise_id: true });
export type UpdateSessionExercise = z.infer<typeof updateSessionExerciseSchema>;

// Reorder — generic reorder payload
export const reorderSchema = z.array(
  z.object({
    id: z.string().uuid(),
    orderIndex: z.number().int().min(0),
  })
);
export type ReorderItem = z.infer<typeof reorderSchema>[number];
