"use server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { requireUser, requireOwnership, OwnershipError } from "@/lib/auth";
import { z, createSessionSchema, reorderSchema } from "@tnw/zod-schemas";

const sessionFormSchema = createSessionSchema.omit({ user_id: true }).extend({
  name: z.string().min(1, "El nombre es obligatorio"),
});

export type SessionFormState = {
  error?: Record<string, string[]>;
  message?: string;
};

export async function createSessionAction(
  _prev: SessionFormState,
  formData: FormData
): Promise<SessionFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const parsed = sessionFormSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
    rest_between_exercises_seconds: Number(formData.get("rest_between_exercises_seconds")) || 60,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { data: session, error } = await supabase
    .from("sessions")
    .insert({
      user_id: user.id,
      name: parsed.data.name,
      description: parsed.data.description ?? null,
      rest_between_exercises_seconds: parsed.data.rest_between_exercises_seconds,
    })
    .select("id")
    .single();

  if (error) return { message: error.message };

  revalidatePath("/dashboard/sessions");
  redirect(`/dashboard/sessions/${session.id}`);
}

export async function updateSessionAction(
  id: string,
  _prev: SessionFormState,
  formData: FormData
): Promise<SessionFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const parsed = sessionFormSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
    rest_between_exercises_seconds: Number(formData.get("rest_between_exercises_seconds")) || 60,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { error } = await supabase
    .from("sessions")
    .update({
      name: parsed.data.name,
      description: parsed.data.description ?? null,
      rest_between_exercises_seconds: parsed.data.rest_between_exercises_seconds,
    })
    .eq("id", id)
    .eq("user_id", user.id);

  if (error) return { message: error.message };

  revalidatePath("/dashboard/sessions");
  revalidatePath(`/dashboard/sessions/${id}`);
  return { message: "Sesión actualizada correctamente" };
}

export async function deleteSessionAction(id: string): Promise<void> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  await supabase.from("sessions").delete().eq("id", id).eq("user_id", user.id);

  revalidatePath("/dashboard/sessions");
  redirect("/dashboard/sessions");
}

export async function reorderSessionExercisesAction(
  sessionId: string,
  items: { id: string; orderIndex: number }[]
): Promise<{ error?: string }> {
  const parsed = reorderSchema.safeParse(items);
  if (!parsed.success) return { error: "Datos inválidos" };

  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "sessions", sessionId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { error } = await supabase.rpc("reorder_items", {
    p_table: "session_exercises",
    p_parent_col: "session_id",
    p_parent_id: sessionId,
    p_items: parsed.data.map(({ id, orderIndex }) => ({ id, order_index: orderIndex })),
  });

  if (error) {
    if (error.message === "unauthorized") return { error: "No autorizado" };
    if (error.message === "invalid_table" || error.message === "invalid_payload") {
      return { error: "Datos inválidos" };
    }
    return { error: error.message };
  }

  revalidatePath(`/dashboard/sessions/${sessionId}`);
  return {};
}

export async function addExerciseToSessionAction(
  sessionId: string,
  exerciseId: string
): Promise<{ error?: string }> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "sessions", sessionId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { data: last } = await supabase
    .from("session_exercises")
    .select("order_index")
    .eq("session_id", sessionId)
    .order("order_index", { ascending: false })
    .limit(1)
    .maybeSingle();

  const nextIndex = last ? last.order_index + 1 : 0;

  const { error } = await supabase.from("session_exercises").insert({
    session_id: sessionId,
    exercise_id: exerciseId,
    order_index: nextIndex,
  });

  if (error) return { error: error.message };

  revalidatePath(`/dashboard/sessions/${sessionId}`);
  return {};
}

export async function removeExerciseFromSessionAction(
  sessionExerciseId: string,
  sessionId: string
): Promise<{ error?: string }> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "sessions", sessionId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { error } = await supabase.from("session_exercises").delete().eq("id", sessionExerciseId);
  if (error) return { error: error.message };

  revalidatePath(`/dashboard/sessions/${sessionId}`);
  return {};
}
