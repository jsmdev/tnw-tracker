import { createClient } from "@/lib/supabase/server";
import Link from "next/link";
import { deletePlanAction } from "@/app/actions/plan";
import { DeleteButton } from "@/components/DeleteButton";

export default async function PlansPage() {
  const supabase = await createClient();
  const { data: plans } = await supabase
    .from("plans")
    .select("id, name, description, duration_weeks")
    .eq("is_active", true)
    .order("name");

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Planes</h1>
        <Link
          href="/dashboard/plans/new"
          className="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 transition-colors"
        >
          + Nuevo plan
        </Link>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-500 uppercase text-xs tracking-wide">
            <tr>
              <th className="px-6 py-3 text-left">Nombre</th>
              <th className="px-6 py-3 text-left">Descripción</th>
              <th className="px-6 py-3 text-left">Duración</th>
              <th className="px-6 py-3 text-right">Acciones</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {plans?.map((p) => (
              <tr key={p.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 font-medium text-gray-900">{p.name}</td>
                <td className="px-6 py-4 text-gray-500 text-xs">
                  {p.description ?? <span className="text-gray-300">—</span>}
                </td>
                <td className="px-6 py-4 text-gray-500">
                  {p.duration_weeks ? (
                    `${p.duration_weeks} sem.`
                  ) : (
                    <span className="text-gray-300">—</span>
                  )}
                </td>
                <td className="px-6 py-4 text-right space-x-3">
                  <Link
                    href={`/dashboard/plans/${p.id}`}
                    className="text-blue-600 hover:text-blue-800 font-medium"
                  >
                    Editar
                  </Link>
                  <DeleteButton
                    action={deletePlanAction.bind(null, p.id)}
                    confirmMessage={`¿Eliminar "${p.name}"?`}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {(!plans || plans.length === 0) && (
          <p className="px-6 py-12 text-center text-gray-400">
            No hay planes.{" "}
            <Link href="/dashboard/plans/new" className="text-blue-600 hover:underline">
              Crea el primero
            </Link>
            .
          </p>
        )}
      </div>
    </div>
  );
}
