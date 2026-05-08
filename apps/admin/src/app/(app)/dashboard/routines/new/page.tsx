import Link from "next/link";
import { RoutineForm } from "@/components/routine/RoutineForm";

export default function NewRoutinePage() {
  return (
    <div className="max-w-2xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/routines" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Rutinas
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">Nueva rutina</h1>
      </div>

      <div className="bg-white rounded-xl shadow p-8">
        <RoutineForm />
      </div>
    </div>
  );
}
