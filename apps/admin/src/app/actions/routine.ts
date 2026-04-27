"use server";
import { z } from "zod";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

const routineFormSchema = z.object({
  name: z.string().min(1, "El nombre es obligatorio"),
  description: z.string().optional(),
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
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

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
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

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
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  await supabase.from("routines").update({ is_active: false }).eq("id", id).eq("user_id", user.id);

  revalidatePath("/dashboard/routines");
  redirect("/dashboard/routines");
}

const reorderItemsSchema = z.array(
  z.object({
    id: z.string().uuid(),
    orderIndex: z.number().int().min(0),
  })
);

export async function reorderRoutineSessionsAction(
  routineId: string,
  items: { id: string; orderIndex: number }[]
): Promise<{ error?: string }> {
  const parsed = reorderItemsSchema.safeParse(items);
  if (!parsed.success) return { error: "Datos inválidos" };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "No autenticado" };

  // Fase 1: valores negativos únicos para evitar conflictos con UNIQUE (routine_id, order_index)
  for (let i = 0; i < parsed.data.length; i++) {
    await supabase
      .from("routine_sessions")
      .update({ order_index: -(i + 1) })
      .eq("id", parsed.data[i].id);
  }
  // Fase 2: valores finales
  for (const item of parsed.data) {
    await supabase
      .from("routine_sessions")
      .update({ order_index: item.orderIndex })
      .eq("id", item.id);
  }

  revalidatePath(`/dashboard/routines/${routineId}`);
  return {};
}

export async function addSessionToRoutineAction(
  routineId: string,
  sessionId: string
): Promise<{ error?: string }> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: "No autenticado" };

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
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: toRemove } = await supabase
    .from("routine_sessions")
    .select("order_index")
    .eq("id", routineSessionId)
    .single();

  await supabase.from("routine_sessions").delete().eq("id", routineSessionId);

  if (toRemove) {
    const { data: remaining } = await supabase
      .from("routine_sessions")
      .select("id, order_index")
      .eq("routine_id", routineId)
      .gt("order_index", toRemove.order_index)
      .order("order_index");

    if (remaining) {
      for (const item of remaining) {
        await supabase
          .from("routine_sessions")
          .update({ order_index: item.order_index - 1 })
          .eq("id", item.id);
      }
    }
  }

  revalidatePath(`/dashboard/routines/${routineId}`);
}
