import { z } from "zod";

// Plan — read
export const planSchema = z.object({
  id: z.string().uuid(),
  user_id: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable(),
  is_active: z.boolean(),
  created_at: z.string().datetime().optional(),
  updated_at: z.string().datetime().optional(),
});
export type Plan = z.infer<typeof planSchema>;

// Plan — insert
export const createPlanSchema = z.object({
  user_id: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().nullable().optional(),
  is_active: z.boolean().optional(),
});
export type CreatePlan = z.infer<typeof createPlanSchema>;

// Plan — update
export const updatePlanSchema = createPlanSchema.partial().omit({ user_id: true });
export type UpdatePlan = z.infer<typeof updatePlanSchema>;

// PlanRoutine — read (join table: plan ↔ routine with order)
export const planRoutineSchema = z.object({
  id: z.string().uuid(),
  plan_id: z.string().uuid(),
  routine_id: z.string().uuid(),
  order_index: z.number().int().min(0),
  created_at: z.string().datetime().optional(),
});
export type PlanRoutine = z.infer<typeof planRoutineSchema>;

// PlanRoutine — insert
export const createPlanRoutineSchema = z.object({
  plan_id: z.string().uuid(),
  routine_id: z.string().uuid(),
  order_index: z.number().int().min(0),
});
export type CreatePlanRoutine = z.infer<typeof createPlanRoutineSchema>;
