import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { SessionForm } from "@/components/session/SessionForm";
import { SessionExercisesDnd } from "@/components/session/SessionExercisesDnd";
import { ExerciseCombobox } from "@/components/session/ExerciseCombobox";
import { CloneButton } from "@/components/CloneButton";

export default async function SessionPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: session }, { data: sessionExercises }, { data: allExercises }] = await Promise.all(
    [
      supabase
        .from("sessions")
        .select("id, name, description, rest_between_exercises_seconds")
        .eq("id", id)
        .single(),
      supabase
        .from("session_exercises")
        .select(
          "id, order_index, target_sets, target_reps, rest_between_sets_seconds, notes, exercise:exercises(id, name, category)"
        )
        .eq("session_id", id)
        .order("order_index"),
      supabase.from("exercises").select("id, name, category").eq("is_active", true).order("name"),
    ]
  );

  if (!session) notFound();

  const exercises = (sessionExercises ?? []).map((se) => ({
    id: se.id,
    order_index: se.order_index,
    target_sets: se.target_sets,
    target_reps: se.target_reps,
    rest_between_sets_seconds: se.rest_between_sets_seconds,
    notes: se.notes,
    exercise: Array.isArray(se.exercise) ? se.exercise[0] : se.exercise,
  }));

  return (
    <div className="max-w-3xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/sessions" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Sesiones
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">{session.name}</h1>
        <CloneButton cloneUrl={`/dashboard/sessions/${id}/clone`} />
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <div className="bg-white rounded-xl shadow p-6">
            <h2 className="text-base font-semibold text-gray-900 mb-4">Datos de la sesión</h2>
            <SessionForm
              session={{
                id: session.id,
                name: session.name,
                description: session.description,
                rest_between_exercises_seconds: session.rest_between_exercises_seconds,
              }}
            />
          </div>
        </div>

        <div className="lg:col-span-3">
          <div className="bg-white rounded-xl shadow p-6">
            <h2 className="text-base font-semibold text-gray-900 mb-4">
              Ejercicios ({exercises.length})
            </h2>

            <div className="mb-4">
              <ExerciseCombobox sessionId={session.id} exercises={allExercises ?? []} />
            </div>

            <SessionExercisesDnd
              sessionId={session.id}
              initial={exercises as Parameters<typeof SessionExercisesDnd>[0]["initial"]}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
