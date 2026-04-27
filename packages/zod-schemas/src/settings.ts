import { z } from "zod";
import { weightUnitSchema, timerTriggerModeSchema } from "./enums";

// UserSettings — read/update
export const userSettingsSchema = z.object({
  weight_unit: weightUnitSchema,
  timer_trigger_mode: timerTriggerModeSchema,
});
export type UserSettings = z.infer<typeof userSettingsSchema>;

// UserSettings — partial update
export const updateUserSettingsSchema = userSettingsSchema.partial();
export type UpdateUserSettings = z.infer<typeof updateUserSettingsSchema>;
