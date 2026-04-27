import { z } from "zod";

// Routine — read
export const routineSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type Routine = z.infer<typeof routineSchema>;

// Routine — insert
export const createRoutineSchema = z.object({
  user_id: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable().optional(),
});
export type CreateRoutine = z.infer<typeof createRoutineSchema>;

// Routine — update
export const updateRoutineSchema = createRoutineSchema.partial().omit({ user_id: true });
export type UpdateRoutine = z.infer<typeof updateRoutineSchema>;

// RoutineSession — read (join table: routine ↔ session with order)
export const routineSessionSchema = z.object({
  id: z.string().uuid(),
  routine_id: z.string().uuid(),
  session_id: z.string().uuid(),
  order_index: z.number().int().min(0),
  created_at: z.string().datetime().optional(),
});
export type RoutineSession = z.infer<typeof routineSessionSchema>;

// RoutineSession — insert
export const createRoutineSessionSchema = z.object({
  routine_id: z.string().uuid(),
  session_id: z.string().uuid(),
  order_index: z.number().int().min(0),
});
export type CreateRoutineSession = z.infer<typeof createRoutineSessionSchema>;
