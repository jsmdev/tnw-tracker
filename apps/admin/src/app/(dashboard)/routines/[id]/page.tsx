import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { RoutineForm } from "@/components/routine/RoutineForm";
import { RoutineSessionsDnd } from "@/components/routine/RoutineSessionsDnd";
import { SessionCombobox } from "@/components/routine/SessionCombobox";

export default async function RoutinePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: routine }, { data: routineSessions }, { data: allSessions }] = await Promise.all([
    supabase
      .from("routines")
      .select("id, name, description")
      .eq("id", id)
      .eq("is_active", true)
      .single(),
    supabase
      .from("routine_sessions")
      .select("id, order_index, session:sessions(id, name)")
      .eq("routine_id", id)
      .order("order_index"),
    supabase.from("sessions").select("id, name").order("name"),
  ]);

  if (!routine) notFound();

  const sessions = (routineSessions ?? []).map((rs) => ({
    id: rs.id,
    order_index: rs.order_index,
    session: Array.isArray(rs.session) ? rs.session[0] : rs.session,
  }));

  return (
    <div className="max-w-3xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/routines" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Rutinas
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">{routine.name}</h1>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <div className="bg-white rounded-xl shadow p-6">
            <h2 className="text-base font-semibold text-gray-900 mb-4">Datos de la rutina</h2>
            <RoutineForm
              routine={{
                id: routine.id,
                name: routine.name,
                description: routine.description,
              }}
            />
          </div>
        </div>

        <div className="lg:col-span-3">
          <div className="bg-white rounded-xl shadow p-6">
            <h2 className="text-base font-semibold text-gray-900 mb-4">
              Sesiones ({sessions.length})
            </h2>

            <div className="mb-4">
              <SessionCombobox routineId={routine.id} sessions={allSessions ?? []} />
            </div>

            <RoutineSessionsDnd
              routineId={routine.id}
              initial={sessions as Parameters<typeof RoutineSessionsDnd>[0]["initial"]}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
