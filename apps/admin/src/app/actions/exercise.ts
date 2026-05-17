"use server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { requireUser, requireOwnership, OwnershipError } from "@/lib/auth";
import { z, createExerciseSchema } from "@tnw/zod-schemas";

const exerciseFormSchema = createExerciseSchema.omit({ user_id: true }).extend({
  name: z.string().min(1, "El nombre es obligatorio"),
  muscle_groups: z.array(z.string()).min(1, "Selecciona al menos un grupo muscular"),
});

export type ExerciseFormState = {
  error?: Record<string, string[]>;
  message?: string;
};

export async function createExerciseAction(
  _prev: ExerciseFormState,
  formData: FormData
): Promise<ExerciseFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const parsed = exerciseFormSchema.safeParse({
    name: formData.get("name"),
    category: formData.get("category"),
    muscle_groups: formData.getAll("muscle_groups"),
    instructions: formData.get("instructions") || undefined,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { data: exercise, error } = await supabase
    .from("exercises")
    .insert({
      user_id: user.id,
      name: parsed.data.name,
      category: parsed.data.category,
      muscle_groups: parsed.data.muscle_groups,
      instructions: parsed.data.instructions ?? null,
    })
    .select("id")
    .single();

  if (error) return { message: error.message };

  revalidatePath("/dashboard/exercises");
  redirect(`/dashboard/exercises/${exercise.id}`);
}

export async function updateExerciseAction(
  id: string,
  _prev: ExerciseFormState,
  formData: FormData
): Promise<ExerciseFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const parsed = exerciseFormSchema.safeParse({
    name: formData.get("name"),
    category: formData.get("category"),
    muscle_groups: formData.getAll("muscle_groups"),
    instructions: formData.get("instructions") || undefined,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { error } = await supabase
    .from("exercises")
    .update({
      name: parsed.data.name,
      category: parsed.data.category,
      muscle_groups: parsed.data.muscle_groups,
      instructions: parsed.data.instructions ?? null,
    })
    .eq("id", id)
    .eq("user_id", user.id);

  if (error) return { message: error.message };

  revalidatePath("/dashboard/exercises");
  revalidatePath(`/dashboard/exercises/${id}`);
  return { message: "Ejercicio actualizado correctamente" };
}

export async function deleteExerciseAction(id: string): Promise<void> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  await supabase.from("exercises").update({ is_active: false }).eq("id", id).eq("user_id", user.id);

  revalidatePath("/dashboard/exercises");
  redirect("/dashboard/exercises");
}

export async function createExerciseVideoAction(
  exerciseId: string,
  url: string,
  source: "storage" | "youtube"
): Promise<{ error?: string }> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "exercises", exerciseId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { error } = await supabase.from("exercise_videos").insert({
    exercise_id: exerciseId,
    source,
    url,
  });

  if (error) return { error: error.message };

  revalidatePath(`/dashboard/exercises/${exerciseId}`);
  return {};
}

export async function deleteExerciseVideoAction(
  videoId: string,
  exerciseId: string
): Promise<{ error?: string }> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "exercises", exerciseId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { error } = await supabase.from("exercise_videos").delete().eq("id", videoId);
  if (error) return { error: error.message };

  revalidatePath(`/dashboard/exercises/${exerciseId}`);
  return {};
}
