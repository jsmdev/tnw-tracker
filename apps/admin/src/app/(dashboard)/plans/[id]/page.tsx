import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { PlanForm } from "@/components/plan/PlanForm";
import { PlanRoutinesDnd } from "@/components/plan/PlanRoutinesDnd";
import { RoutineCombobox } from "@/components/plan/RoutineCombobox";

export default async function PlanPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: plan }, { data: planRoutines }, { data: allRoutines }] = await Promise.all([
    supabase
      .from("plans")
      .select("id, name, description, duration_weeks")
      .eq("id", id)
      .eq("is_active", true)
      .single(),
    supabase
      .from("plan_routines")
      .select("id, order_index, routine:routines(id, name)")
      .eq("plan_id", id)
      .order("order_index"),
    supabase.from("routines").select("id, name").eq("is_active", true).order("name"),
  ]);

  if (!plan) notFound();

  const routines = (planRoutines ?? []).map((pr) => ({
    id: pr.id,
    order_index: pr.order_index,
    routine: Array.isArray(pr.routine) ? pr.routine[0] : pr.routine,
  }));

  return (
    <div className="max-w-3xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/plans" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Planes
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">{plan.name}</h1>
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <div className="bg-white rounded-xl shadow p-6">
            <h2 className="text-base font-semibold text-gray-900 mb-4">Datos del plan</h2>
            <PlanForm
              plan={{
                id: plan.id,
                name: plan.name,
                description: plan.description,
                duration_weeks: plan.duration_weeks,
              }}
            />
          </div>
        </div>

        <div className="lg:col-span-3">
          <div className="bg-white rounded-xl shadow p-6">
            <h2 className="text-base font-semibold text-gray-900 mb-4">
              Rutinas ({routines.length})
            </h2>

            <div className="mb-4">
              <RoutineCombobox planId={plan.id} routines={allRoutines ?? []} />
            </div>

            <PlanRoutinesDnd
              planId={plan.id}
              initial={routines as Parameters<typeof PlanRoutinesDnd>[0]["initial"]}
            />
          </div>
        </div>
      </div>
    </div>
  );
}
