import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { WorkoutSetList } from "@/components/workout/WorkoutSetList";

function formatDuration(seconds: number | null) {
  if (seconds == null) return "—";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return [h, m, s].map((v) => String(v).padStart(2, "0")).join(":");
}

function statusLabel(status: string) {
  const map: Record<string, string> = {
    active: "Activo",
    paused: "Pausado",
    completed: "Completado",
    cancelled: "Cancelado",
  };
  return map[status] ?? status;
}

export default async function WorkoutDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: workout } = await supabase
    .from("workouts")
    .select(
      `id, name, status, started_at, completed_at, duration_seconds, notes,
       workout_exercises (
         id, order_index,
         exercise:exercises ( name, category ),
         exercise_sets (
           id, set_number, reps, weight, weight_unit, rpe,
           is_warmup, is_personal_record, completed_at
         )
       )`
    )
    .eq("id", id)
    .single();

  if (!workout) notFound();

  const workoutExercises = (workout.workout_exercises ?? [])
    .sort((a, b) => a.order_index - b.order_index)
    .map((we) => ({
      ...we,
      exercise: Array.isArray(we.exercise) ? we.exercise[0] : we.exercise,
      exercise_sets: (we.exercise_sets ?? []).sort((a, b) => a.set_number - b.set_number),
    }));

  return (
    <div className="max-w-3xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/workouts" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Entrenamientos
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">{workout.name}</h1>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3 mb-6">
        <div className="bg-white rounded-xl shadow p-4 text-center">
          <p className="text-xs text-gray-500 mb-1">Estado</p>
          <p className="font-semibold text-gray-800">{statusLabel(workout.status)}</p>
        </div>
        <div className="bg-white rounded-xl shadow p-4 text-center">
          <p className="text-xs text-gray-500 mb-1">Inicio</p>
          <p className="font-semibold text-gray-800">
            {new Date(workout.started_at).toLocaleString("es-ES", {
              dateStyle: "short",
              timeStyle: "short",
            })}
          </p>
        </div>
        <div className="bg-white rounded-xl shadow p-4 text-center">
          <p className="text-xs text-gray-500 mb-1">Duración</p>
          <p className="font-semibold text-gray-800">{formatDuration(workout.duration_seconds)}</p>
        </div>
      </div>

      {workout.notes && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4 mb-6 text-sm text-yellow-800">
          {workout.notes}
        </div>
      )}

      <div className="bg-white rounded-xl shadow p-6">
        <h2 className="text-base font-semibold text-gray-900 mb-4">
          Series ({workoutExercises.length} ejercicios)
        </h2>
        <WorkoutSetList workoutExercises={workoutExercises} />
      </div>
    </div>
  );
}
