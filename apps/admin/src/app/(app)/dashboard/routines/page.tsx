import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { deleteRoutineAction } from "@/app/actions/routine";
import { DeleteButton } from "@/components/DeleteButton";

export default async function RoutinesPage() {
  const supabase = await createClient();
  const { data: routines } = await supabase
    .from("routines")
    .select("id, name, description")
    .eq("is_active", true)
    .order("name");

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Rutinas</h1>
        <Link
          href="/dashboard/routines/new"
          className="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 transition-colors"
        >
          + Nueva rutina
        </Link>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-500 uppercase text-xs tracking-wide">
            <tr>
              <th className="px-6 py-3 text-left">Nombre</th>
              <th className="px-6 py-3 text-left">Descripción</th>
              <th className="px-6 py-3 text-right">Acciones</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {routines?.map((r) => (
              <tr key={r.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 font-medium text-gray-900">{r.name}</td>
                <td className="px-6 py-4 text-gray-500 text-xs">
                  {r.description ?? <span className="text-gray-300">—</span>}
                </td>
                <td className="px-6 py-4 text-right space-x-3">
                  <Link
                    href={`/dashboard/routines/${r.id}`}
                    className="text-blue-600 hover:text-blue-800 font-medium"
                  >
                    Editar
                  </Link>
                  <DeleteButton
                    action={deleteRoutineAction.bind(null, r.id)}
                    confirmMessage={`¿Eliminar "${r.name}"?`}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!routines || routines.length === 0) && (
          <p className="px-6 py-12 text-center text-gray-400">
            No hay rutinas.{" "}
            <Link href="/dashboard/routines/new" className="text-blue-600 hover:underline">
              Crea la primera
            </Link>
            .
          </p>
        )}
      </div>
    </div>
  );
}
