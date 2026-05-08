"use server";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { requireUser, requireOwnership, OwnershipError } from "@/lib/auth";
import { z, createPlanSchema, reorderSchema } from "@tnw/zod-schemas";

const planFormSchema = createPlanSchema.omit({ user_id: true }).extend({
  name: z.string().min(1, "El nombre es obligatorio"),
});

export type PlanFormState = {
  error?: Record<string, string[]>;
  message?: string;
};

export async function createPlanAction(
  _prev: PlanFormState,
  formData: FormData
): Promise<PlanFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const rawWeeks = formData.get("duration_weeks");
  const parsed = planFormSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
    duration_weeks: rawWeeks ? Number(rawWeeks) : undefined,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { data: plan, error } = await supabase
    .from("plans")
    .insert({
      user_id: user.id,
      name: parsed.data.name,
      description: parsed.data.description ?? null,
      duration_weeks: parsed.data.duration_weeks ?? null,
    })
    .select("id")
    .single();

  if (error) return { message: error.message };

  revalidatePath("/dashboard/plans");
  redirect(`/dashboard/plans/${plan.id}`);
}

export async function updatePlanAction(
  id: string,
  _prev: PlanFormState,
  formData: FormData
): Promise<PlanFormState> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  const rawWeeks = formData.get("duration_weeks");
  const parsed = planFormSchema.safeParse({
    name: formData.get("name"),
    description: formData.get("description") || undefined,
    duration_weeks: rawWeeks ? Number(rawWeeks) : undefined,
  });

  if (!parsed.success) return { error: parsed.error.flatten().fieldErrors };

  const { error } = await supabase
    .from("plans")
    .update({
      name: parsed.data.name,
      description: parsed.data.description ?? null,
      duration_weeks: parsed.data.duration_weeks ?? null,
    })
    .eq("id", id)
    .eq("user_id", user.id);

  if (error) return { message: error.message };

  revalidatePath("/dashboard/plans");
  revalidatePath(`/dashboard/plans/${id}`);
  return { message: "Plan actualizado correctamente" };
}

export async function deletePlanAction(id: string): Promise<void> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  await supabase.from("plans").update({ is_active: false }).eq("id", id).eq("user_id", user.id);

  revalidatePath("/dashboard/plans");
  redirect("/dashboard/plans");
}

export async function reorderPlanRoutinesAction(
  planId: string,
  items: { id: string; orderIndex: number }[]
): Promise<{ error?: string }> {
  const parsed = reorderSchema.safeParse(items);
  if (!parsed.success) return { error: "Datos inválidos" };

  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "plans", planId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  // Fase 1: valores negativos únicos para evitar conflictos con UNIQUE (plan_id, order_index)
  for (let i = 0; i < parsed.data.length; i++) {
    await supabase
      .from("plan_routines")
      .update({ order_index: -(i + 1) })
      .eq("id", parsed.data[i].id);
  }
  // Fase 2: valores finales
  for (const item of parsed.data) {
    await supabase.from("plan_routines").update({ order_index: item.orderIndex }).eq("id", item.id);
  }

  revalidatePath(`/dashboard/plans/${planId}`);
  return {};
}

export async function addRoutineToPlanAction(
  planId: string,
  routineId: string
): Promise<{ error?: string }> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "plans", planId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return { error: "No autorizado" };
    throw e;
  }

  const { data: last } = await supabase
    .from("plan_routines")
    .select("order_index")
    .eq("plan_id", planId)
    .order("order_index", { ascending: false })
    .limit(1)
    .maybeSingle();

  const nextIndex = last ? last.order_index + 1 : 0;

  const { error } = await supabase.from("plan_routines").insert({
    plan_id: planId,
    routine_id: routineId,
    order_index: nextIndex,
  });

  if (error) return { error: error.message };

  revalidatePath(`/dashboard/plans/${planId}`);
  return {};
}

export async function removeRoutineFromPlanAction(
  planRoutineId: string,
  planId: string
): Promise<void> {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  try {
    await requireOwnership(supabase, "plans", planId, user.id);
  } catch (e) {
    if (e instanceof OwnershipError) return;
    throw e;
  }

  const { data: toRemove } = await supabase
    .from("plan_routines")
    .select("order_index")
    .eq("id", planRoutineId)
    .single();

  await supabase.from("plan_routines").delete().eq("id", planRoutineId);

  if (toRemove) {
    const { data: remaining } = await supabase
      .from("plan_routines")
      .select("id, order_index")
      .eq("plan_id", planId)
      .gt("order_index", toRemove.order_index)
      .order("order_index");

    if (remaining) {
      for (const item of remaining) {
        await supabase
          .from("plan_routines")
          .update({ order_index: item.order_index - 1 })
          .eq("id", item.id);
      }
    }
  }

  revalidatePath(`/dashboard/plans/${planId}`);
}
