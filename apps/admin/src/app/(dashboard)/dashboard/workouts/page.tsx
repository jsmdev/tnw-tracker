import { createClient } from "@/lib/supabase/server";
import Link from "next/link";

const PAGE_SIZE = 20;

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

function statusColor(status: string) {
  const map: Record<string, string> = {
    active: "bg-green-100 text-green-700",
    paused: "bg-yellow-100 text-yellow-700",
    completed: "bg-blue-100 text-blue-700",
    cancelled: "bg-gray-100 text-gray-500",
  };
  return map[status] ?? "bg-gray-100 text-gray-500";
}

export default async function WorkoutsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string }>;
}) {
  const { page: pageStr } = await searchParams;
  const page = Math.max(1, parseInt(pageStr ?? "1", 10));
  const from = (page - 1) * PAGE_SIZE;
  const to = from + PAGE_SIZE - 1;

  const supabase = await createClient();

  const { data: workouts, count } = await supabase
    .from("workouts")
    .select("id, name, status, started_at, completed_at, duration_seconds", {
      count: "exact",
    })
    .order("started_at", { ascending: false })
    .range(from, to);

  const totalPages = Math.ceil((count ?? 0) / PAGE_SIZE);

  return (
    <div className="max-w-4xl">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Entrenamientos</h1>
        <span className="text-sm text-gray-500">{count ?? 0} en total</span>
      </div>

      <div className="bg-white rounded-xl shadow overflow-hidden">
        {!workouts || workouts.length === 0 ? (
          <p className="p-6 text-sm text-gray-500">No hay entrenamientos registrados.</p>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-gray-50 border-b border-gray-200">
              <tr>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Nombre</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Estado</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Inicio</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Duración</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {workouts.map((w) => (
                <tr key={w.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3">
                    <Link
                      href={`/dashboard/workouts/${w.id}`}
                      className="font-medium text-blue-600 hover:underline"
                    >
                      {w.name}
                    </Link>
                  </td>
                  <td className="px-4 py-3">
                    <span
                      className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${statusColor(w.status)}`}
                    >
                      {statusLabel(w.status)}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-600">
                    {new Date(w.started_at).toLocaleString("es-ES", {
                      dateStyle: "short",
                      timeStyle: "short",
                    })}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{formatDuration(w.duration_seconds)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {totalPages > 1 && (
        <div className="flex items-center justify-between mt-4 text-sm">
          <span className="text-gray-500">
            Página {page} de {totalPages}
          </span>
          <div className="flex gap-2">
            {page > 1 && (
              <Link
                href={`/dashboard/workouts?page=${page - 1}`}
                className="px-3 py-1.5 border border-gray-200 rounded-lg hover:bg-gray-50"
              >
                ← Anterior
              </Link>
            )}
            {page < totalPages && (
              <Link
                href={`/dashboard/workouts?page=${page + 1}`}
                className="px-3 py-1.5 border border-gray-200 rounded-lg hover:bg-gray-50"
              >
                Siguiente →
              </Link>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
