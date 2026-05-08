"use server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireUser } from "@/lib/auth";
import { userSettingsSchema } from "@tnw/zod-schemas";

export type SettingsFormState = {
  error?: Record<string, string[]>;
  message?: string;
  success?: boolean;
};

export async function updateSettingsAction(
  _prev: SettingsFormState,
  formData: FormData
): Promise<SettingsFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const parsed = userSettingsSchema.safeParse({
    weight_unit: formData.get("weight_unit"),
    timer_trigger_mode: formData.get("timer_trigger_mode"),
  });

  if (!parsed.success) {
    return { error: parsed.error.flatten().fieldErrors };
  }

  const { error } = await supabase.from("users").update(parsed.data).eq("id", user.id);

  if (error) return { message: error.message };

  revalidatePath("/dashboard/settings");
  return { success: true, message: "Ajustes guardados." };
}
