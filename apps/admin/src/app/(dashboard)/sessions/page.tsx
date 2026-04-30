import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { deleteSessionAction } from "@/app/actions/session";
import { DeleteButton } from "@/components/DeleteButton";

export default async function SessionsPage() {
  const supabase = await createClient();
  const { data: sessions } = await supabase
    .from("sessions")
    .select("id, name, description, rest_between_exercises_seconds")
    .order("name");

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Sesiones</h1>
        <Link
          href="/dashboard/sessions/new"
          className="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 transition-colors"
        >
          + Nueva sesión
        </Link>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-500 uppercase text-xs tracking-wide">
            <tr>
              <th className="px-6 py-3 text-left">Nombre</th>
              <th className="px-6 py-3 text-left">Descripción</th>
              <th className="px-6 py-3 text-left">Descanso entre ejercicios</th>
              <th className="px-6 py-3 text-right">Acciones</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {sessions?.map((s) => (
              <tr key={s.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 font-medium text-gray-900">{s.name}</td>
                <td className="px-6 py-4 text-gray-500 text-xs">
                  {s.description ?? <span className="text-gray-300">—</span>}
                </td>
                <td className="px-6 py-4 text-gray-500">{s.rest_between_exercises_seconds}s</td>
                <td className="px-6 py-4 text-right space-x-3">
                  <Link
                    href={`/dashboard/sessions/${s.id}`}
                    className="text-blue-600 hover:text-blue-800 font-medium"
                  >
                    Editar
                  </Link>
                  <DeleteButton
                    action={deleteSessionAction.bind(null, s.id)}
                    confirmMessage={`¿Eliminar "${s.name}"?`}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!sessions || sessions.length === 0) && (
          <p className="px-6 py-12 text-center text-gray-400">
            No hay sesiones.{" "}
            <Link href="/dashboard/sessions/new" className="text-blue-600 hover:underline">
              Crea la primera
            </Link>
            .
          </p>
        )}
      </div>
    </div>
  );
}
