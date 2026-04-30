import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { deleteExerciseAction } from "@/app/actions/exercise";
import { DeleteButton } from "@/components/DeleteButton";

export default async function ExercisesPage() {
  const supabase = await createClient();
  const { data: exercises } = await supabase
    .from("exercises")
    .select("id, name, category, muscle_groups")
    .eq("is_active", true)
    .order("name");

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Ejercicios</h1>
        <Link
          href="/dashboard/exercises/new"
          className="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 transition-colors"
        >
          + Nuevo ejercicio
        </Link>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-500 uppercase text-xs tracking-wide">
            <tr>
              <th className="px-6 py-3 text-left">Nombre</th>
              <th className="px-6 py-3 text-left">Categoría</th>
              <th className="px-6 py-3 text-left">Grupos musculares</th>
              <th className="px-6 py-3 text-right">Acciones</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {exercises?.map((e) => (
              <tr key={e.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 font-medium text-gray-900">{e.name}</td>
                <td className="px-6 py-4">
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-50 text-blue-700">
                    {e.category}
                  </span>
                </td>
                <td className="px-6 py-4 text-gray-500 text-xs">
                  {(e.muscle_groups as string[]).join(", ")}
                </td>
                <td className="px-6 py-4 text-right space-x-3">
                  <Link
                    href={`/dashboard/exercises/${e.id}`}
                    className="text-blue-600 hover:text-blue-800 font-medium"
                  >
                    Editar
                  </Link>
                  <DeleteButton
                    action={deleteExerciseAction.bind(null, e.id)}
                    confirmMessage={`¿Eliminar "${e.name}"?`}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!exercises || exercises.length === 0) && (
          <p className="px-6 py-12 text-center text-gray-400">
            No hay ejercicios.{" "}
            <Link href="/dashboard/exercises/new" className="text-blue-600 hover:underline">
              Crea el primero
            </Link>
            .
          </p>
        )}
      </div>
    </div>
  );
}
