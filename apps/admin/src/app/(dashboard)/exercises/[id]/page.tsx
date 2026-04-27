import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { ExerciseForm } from "@/components/exercise/ExerciseForm";
import { VideoUploader } from "@/components/exercise/VideoUploader";
import { deleteExerciseVideoAction } from "@/app/actions/exercise";

export default async function ExercisePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: exercise } = await supabase
    .from("exercises")
    .select("id, name, category, muscle_groups, instructions")
    .eq("id", id)
    .eq("is_active", true)
    .single();

  if (!exercise) notFound();

  const { data: videos } = await supabase
    .from("exercise_videos")
    .select("id, source, url, order_index")
    .eq("exercise_id", exercise.id)
    .order("order_index");

  return (
    <div className="max-w-2xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/exercises" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Ejercicios
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">{exercise.name}</h1>
      </div>

      <div className="bg-white rounded-xl shadow p-8">
        <ExerciseForm
          exercise={{
            id: exercise.id,
            name: exercise.name,
            category: exercise.category,
            muscle_groups: exercise.muscle_groups as string[],
            instructions: exercise.instructions,
          }}
        />
      </div>

      <div className="bg-white rounded-xl shadow p-8 mt-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Vídeos</h2>

        {videos && videos.length > 0 && (
          <ul className="mb-6 space-y-2">
            {videos.map((v) => (
              <li
                key={v.id}
                className="flex items-center justify-between bg-gray-50 rounded-lg px-4 py-2.5"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <span className="text-xs font-medium px-2 py-0.5 rounded bg-gray-200 text-gray-600 shrink-0">
                    {v.source === "youtube" ? "YouTube" : "Storage"}
                  </span>
                  <a
                    href={v.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-blue-600 hover:text-blue-800 text-sm truncate"
                  >
                    {v.url}
                  </a>
                </div>
                <form
                  action={deleteExerciseVideoAction.bind(null, v.id, exercise.id)}
                  className="ml-4 shrink-0"
                >
                  <button
                    type="submit"
                    className="text-red-500 hover:text-red-700 text-sm font-medium"
                  >
                    Eliminar
                  </button>
                </form>
              </li>
            ))}
          </ul>
        )}

        {(!videos || videos.length === 0) && (
          <p className="text-sm text-gray-400 mb-6">Sin vídeos. Añade uno a continuación.</p>
        )}

        <VideoUploader exerciseId={exercise.id} />
      </div>
    </div>
  );
}
