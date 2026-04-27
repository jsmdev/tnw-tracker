import Link from "next/link";
import { ExerciseForm } from "@/components/exercise/ExerciseForm";

export default function NewExercisePage() {
  return (
    <div className="max-w-2xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/exercises" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Ejercicios
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">Nuevo ejercicio</h1>
      </div>

      <div className="bg-white rounded-xl shadow p-8">
        <ExerciseForm />
      </div>
    </div>
  );
}
