"use server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { requireUser, requireOwnership, OwnershipError } from "@/lib/auth";
import { z, createRoutineSchema, reorderSchema } from "@tnw/zod-schemas";

const routineFormSchema = createRoutineSchema.omit({ user_id: true }).extend({
  name: z.string().min(1, "El nombre es obligatorio"),
});

export type RoutineFormState = {
  error?: Record<string, string[]>;
  message?: string;
};

export async function createRoutineAction(
  _prev: RoutineFormState,
  formData: FormData
): Promise<RoutineFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const parsed = routineFormSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { data: routine, error } = await supabase
    .from("routines")
    .insert({
      user_id: user.id,
      name: parsed.data.name,
      description: parsed.data.description ?? null,
    })
    .select("id")
    .single();

  if (error) return { message: error.message };

  revalidatePath("/dashboard/routines");
  redirect(`/dashboard/routines/${routine.id}`);
}

export async function updateRoutineAction(
  id: string,
  _prev: RoutineFormState,
  formData: FormData
): Promise<RoutineFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const parsed = routineFormSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { error } = await supabase
    .from("routines")
    .update({
      name: parsed.data.name,
      description: parsed.data.description ?? null,
    })
    .eq("id", id)
    .eq("user_id", user.id);

  if (error) return { message: error.message };

  revalidatePath("/dashboard/routines");
  revalidatePath(`/dashboard/routines/${id}`);
  return { message: "Rutina actualizada correctamente" };
}

export async function deleteRoutineAction(id: string): Promise<void> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  await supabase.from("routines").update({ is_active: false }).eq("id", id).eq("user_id", user.id);

  revalidatePath("/dashboard/routines");
  redirect("/dashboard/routines");
}

export async function reorderRoutineSessionsAction(
  routineId: string,
  items: { id: string; orderIndex: number }[]
): Promise<{ error?: string }> {
  const parsed = reorderSchema.safeParse(items);
  if (!parsed.success) return { error: "Datos inválidos" };

  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "routines", routineId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { error } = await supabase.rpc("reorder_items", {
    p_table: "routine_sessions",
    p_parent_col: "routine_id",
    p_parent_id: routineId,
    p_items: parsed.data.map(({ id, orderIndex }) => ({ id, order_index: orderIndex })),
  });

  if (error) {
    if (error.message === "unauthorized") return { error: "No autorizado" };
    if (error.message === "invalid_table" || error.message === "invalid_payload") {
      return { error: "Datos inválidos" };
    }
    return { error: error.message };
  }

  revalidatePath(`/dashboard/routines/${routineId}`);
  return {};
}

export async function addSessionToRoutineAction(
  routineId: string,
  sessionId: string
): Promise<{ error?: string }> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "routines", routineId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { data: last } = await supabase
    .from("routine_sessions")
    .select("order_index")
    .eq("routine_id", routineId)
    .order("order_index", { ascending: false })
    .limit(1)
    .maybeSingle();

  const nextIndex = last ? last.order_index + 1 : 0;

  const { error } = await supabase.from("routine_sessions").insert({
    routine_id: routineId,
    session_id: sessionId,
    order_index: nextIndex,
  });

  if (error) return { error: error.message };

  revalidatePath(`/dashboard/routines/${routineId}`);
  return {};
}

export async function removeSessionFromRoutineAction(
  routineSessionId: string,
  routineId: string
): Promise<void> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "routines", routineId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return;
    throw e;
  }

  await supabase.from("routine_sessions").delete().eq("id", routineSessionId);

  revalidatePath(`/dashboard/routines/${routineId}`);
}
