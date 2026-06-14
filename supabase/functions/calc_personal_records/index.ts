import { createClient } from "jsr:@supabase/supabase-js@2";
import { ALL_TYPES, computeBestRecords, type SetRow } from "./records.ts";

interface Payload {
  workout_id: string;
}

// MARK: - Handler

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return new Response("Unauthorized", { status: 401 });

  let payload: Payload;
  try {
    payload = (await req.json()) as Payload;
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  if (!payload.workout_id) {
    return new Response("workout_id required", { status: 400 });
  }

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data: workout } = await sb
    .from("workouts")
    .select("id, user_id")
    .eq("id", payload.workout_id)
    .single();

  if (!workout) return new Response("Workout not found", { status: 404 });

  // Ejercicios afectados por este workout (los únicos cuyos PRs pueden cambiar).
  const { data: wes } = await sb
    .from("workout_exercises")
    .select("exercise_id")
    .eq("workout_id", payload.workout_id);

  const exerciseIds = [...new Set((wes ?? []).map((w) => w.exercise_id as string))];
  if (exerciseIds.length === 0) {
    return Response.json({ recomputed: 0 });
  }

  let upserts = 0;
  let deletes = 0;
  const allSetIds: string[] = [];
  const prSetIds: string[] = [];

  for (const exerciseId of exerciseIds) {
    // TODAS las series completadas (sin calentamiento) del usuario para este
    // ejercicio, en todos sus workouts — la verdadera base del récord histórico.
    const { data: rawSets } = await sb
      .from("exercise_sets")
      .select(
        "id, reps, weight, weight_unit, completed_at, " +
          "workout_exercise:workout_exercises!inner(exercise_id, workout:workouts!inner(user_id))"
      )
      .eq("workout_exercise.exercise_id", exerciseId)
      .eq("workout_exercise.workout.user_id", workout.user_id)
      .not("completed_at", "is", null)
      .eq("is_warmup", false);

    const sets = (rawSets ?? []) as unknown as SetRow[];
    for (const s of sets) allSetIds.push(s.id);

    const bests = computeBestRecords(sets);
    const bestByType = new Map(bests.map((b) => [b.record_type, b]));

    for (const type of ALL_TYPES) {
      const best = bestByType.get(type);
      if (best) {
        await sb.from("personal_records").upsert(
          {
            user_id: workout.user_id,
            exercise_id: exerciseId,
            exercise_set_id: best.exercise_set_id,
            record_type: type,
            value: best.value,
            weight_unit: "kg",
            achieved_at: best.achieved_at,
          },
          { onConflict: "user_id,exercise_id,record_type" }
        );
        prSetIds.push(best.exercise_set_id);
        upserts++;
      } else {
        // Sin datos para este tipo → el récord vigente ya no tiene respaldo.
        const { count } = await sb
          .from("personal_records")
          .delete({ count: "exact" })
          .eq("user_id", workout.user_id)
          .eq("exercise_id", exerciseId)
          .eq("record_type", type);
        deletes += count ?? 0;
      }
    }
  }

  // Reflejar el flag is_personal_record en las series afectadas: primero a false
  // en todas, luego true en las que sostienen un récord vigente.
  if (allSetIds.length > 0) {
    await sb.from("exercise_sets").update({ is_personal_record: false }).in("id", allSetIds);
  }
  if (prSetIds.length > 0) {
    await sb
      .from("exercise_sets")
      .update({ is_personal_record: true })
      .in("id", [...new Set(prSetIds)]);
  }

  return Response.json({ recomputed: exerciseIds.length, upserts, deletes });
});
