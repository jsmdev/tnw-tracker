"use client";
import { useActionState } from "react";
import {
  createExerciseAction,
  updateExerciseAction,
  type ExerciseFormState,
} from "@/app/actions/exercise";

const CATEGORIES = ["Push", "Pull", "Legs", "Core", "Cardio", "Other"] as const;

const MUSCLE_GROUPS = [
  "Pecho",
  "Espalda alta",
  "Espalda baja",
  "Hombros",
  "Bíceps",
  "Tríceps",
  "Antebrazo",
  "Abdominales",
  "Oblicuos",
  "Glúteos",
  "Cuádriceps",
  "Isquiotibiales",
  "Pantorrillas",
  "Trapecio",
];

interface ExerciseData {
  id: string;
  name: string;
  category: string;
  muscle_groups: string[];
  instructions: string | null;
}

interface Props {
  exercise?: ExerciseData;
}

export function ExerciseForm({ exercise }: Props) {
  const action = exercise ? updateExerciseAction.bind(null, exercise.id) : createExerciseAction;

  const [state, formAction, isPending] = useActionState<ExerciseFormState, FormData>(action, {});

  return (
    <form action={formAction} className="space-y-6">
      {state.message && (
        <p
          className={`text-sm rounded-lg px-4 py-2 ${
            state.error ? "bg-red-50 text-red-700" : "bg-green-50 text-green-700"
          }`}
        >
          {state.message}
        </p>
      )}

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Nombre <span className="text-red-500">*</span>
        </label>
        <input
          type="text"
          name="name"
          defaultValue={exercise?.name}
          required
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        {state.error?.name && <p className="mt-1 text-xs text-red-600">{state.error.name[0]}</p>}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Categoría <span className="text-red-500">*</span>
        </label>
        <select
          name="category"
          defaultValue={exercise?.category ?? ""}
          required
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
        >
          <option value="" disabled>
            Selecciona una categoría
          </option>
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
        {state.error?.category && (
          <p className="mt-1 text-xs text-red-600">{state.error.category[0]}</p>
        )}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-2">
          Grupos musculares <span className="text-red-500">*</span>
        </label>
        <div className="grid grid-cols-2 gap-2">
          {MUSCLE_GROUPS.map((mg) => (
            <label key={mg} className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="muscle_groups"
                value={mg}
                defaultChecked={exercise?.muscle_groups.includes(mg)}
                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
              />
              <span className="text-sm text-gray-700">{mg}</span>
            </label>
          ))}
        </div>
        {state.error?.muscle_groups && (
          <p className="mt-1 text-xs text-red-600">{state.error.muscle_groups[0]}</p>
        )}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Instrucciones</label>
        <textarea
          name="instructions"
          defaultValue={exercise?.instructions ?? ""}
          rows={4}
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
          placeholder="Descripción del ejercicio, técnica, consejos..."
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="w-full bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors"
      >
        {isPending
          ? exercise
            ? "Guardando..."
            : "Creando..."
          : exercise
            ? "Guardar cambios"
            : "Crear ejercicio"}
      </button>
    </form>
  );
}
