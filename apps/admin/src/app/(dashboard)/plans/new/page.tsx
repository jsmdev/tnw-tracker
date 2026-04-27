import Link from "next/link";
import { PlanForm } from "@/components/plan/PlanForm";

export default function NewPlanPage() {
  return (
    <div className="max-w-2xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/plans" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Planes
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">Nuevo plan</h1>
      </div>

      <div className="bg-white rounded-xl shadow p-8">
        <PlanForm />
      </div>
    </div>
  );
}
