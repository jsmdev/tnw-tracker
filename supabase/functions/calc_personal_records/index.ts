import { createClient } from "jsr:@supabase/supabase-js@2";

interface Payload {
  workout_id: string;
}

interface ExerciseSetRow {
  id: string;
  reps: number | null;
  weight: number | null;
  weight_unit: string;
  workout_exercise: { exercise_id: string; workout_id: string } | null;
}

interface CurrentPR {
  record_type: string;
  value: number;
  weight_unit: string;
}

interface PRInsert {
  user_id: string;
  exercise_id: string;
  exercise_set_id: string;
  record_type: string;
  value: number;
  weight_unit: string;
}

function toKg(weight: number | null, unit: string): number {
  if (weight == null) return 0;
  return unit === "lb" ? weight * 0.453592 : weight;
}

function bestPR(prs: CurrentPR[], type: string): number {
  const filtered = prs.filter((p) => p.record_type === type);
  if (filtered.length === 0) return 0;
  return Math.max(...filtered.map((p) => (p.weight_unit === "lb" ? p.value * 0.453592 : p.value)));
}

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

  const { data: sets } = await sb
    .from("exercise_sets")
    .select(
      "id, reps, weight, weight_unit, workout_exercise:workout_exercises!inner(exercise_id, workout_id)"
    )
    .eq("workout_exercise.workout_id", payload.workout_id)
    .not("completed_at", "is", null)
    .eq("is_warmup", false);

  if (!sets || sets.length === 0) {
    return Response.json({ created: 0 });
  }

  // Agrupar por exercise_id
  const byExercise = new Map<string, ExerciseSetRow[]>();
  for (const s of sets as ExerciseSetRow[]) {
    const eid = s.workout_exercise?.exercise_id;
    if (!eid) continue;
    if (!byExercise.has(eid)) byExercise.set(eid, []);
    byExercise.get(eid)!.push(s);
  }

  const prsToInsert: PRInsert[] = [];

  for (const [exerciseId, exSets] of byExercise) {
    const { data: currentPRs } = await sb
      .from("personal_records")
      .select("record_type, value, weight_unit")
      .eq("user_id", workout.user_id)
      .eq("exercise_id", exerciseId);

    const bestWeight = bestPR(currentPRs ?? [], "max_weight");
    const bestReps = bestPR(currentPRs ?? [], "max_reps");
    const bestVolume = bestPR(currentPRs ?? [], "max_volume");

    for (const s of exSets) {
      const weightKg = toKg(s.weight, s.weight_unit);
      const volume = (s.reps ?? 0) * weightKg;

      if (weightKg > bestWeight) {
        prsToInsert.push({
          user_id: workout.user_id,
          exercise_id: exerciseId,
          exercise_set_id: s.id,
          record_type: "max_weight",
          value: weightKg,
          weight_unit: "kg",
        });
      }
      if ((s.reps ?? 0) > bestReps) {
        prsToInsert.push({
          user_id: workout.user_id,
          exercise_id: exerciseId,
          exercise_set_id: s.id,
          record_type: "max_reps",
          value: s.reps ?? 0,
          weight_unit: "kg",
        });
      }
      if (volume > bestVolume) {
        prsToInsert.push({
          user_id: workout.user_id,
          exercise_id: exerciseId,
          exercise_set_id: s.id,
          record_type: "max_volume",
          value: volume,
          weight_unit: "kg",
        });
      }
    }
  }

  if (prsToInsert.length > 0) {
    await sb.from("personal_records").insert(prsToInsert);
    await sb
      .from("exercise_sets")
      .update({ is_personal_record: true })
      .in(
        "id",
        prsToInsert.map((p) => p.exercise_set_id)
      );
  }

  return Response.json({ created: prsToInsert.length });
});
