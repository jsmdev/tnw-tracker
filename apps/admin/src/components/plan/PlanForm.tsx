"use client";
import { useActionState } from "react";
import { createPlanAction, updatePlanAction, type PlanFormState } from "@/app/actions/plan";

interface PlanData {
  id: string;
  name: string;
  description: string | null;
  duration_weeks: number | null;
}

interface Props {
  plan?: PlanData;
}

export function PlanForm({ plan }: Props) {
  const action = plan ? updatePlanAction.bind(null, plan.id) : createPlanAction;

  const [state, formAction, isPending] = useActionState<PlanFormState, FormData>(action, {});

  return (
    <form action={formAction} className="space-y-5">
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
        <label htmlFor="plan-name" className="block text-sm font-medium text-gray-700 mb-1">
          Nombre <span className="text-red-500">*</span>
        </label>
        <input
          id="plan-name"
          type="text"
          name="name"
          defaultValue={plan?.name}
          required
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        {state.error?.name && <p className="mt-1 text-xs text-red-600">{state.error.name[0]}</p>}
      </div>

      <div>
        <label htmlFor="plan-description" className="block text-sm font-medium text-gray-700 mb-1">
          Descripción
        </label>
        <textarea
          id="plan-description"
          name="description"
          defaultValue={plan?.description ?? ""}
          rows={3}
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
          placeholder="Descripción opcional del plan..."
        />
      </div>

      <div>
        <label
          htmlFor="plan-duration-weeks"
          className="block text-sm font-medium text-gray-700 mb-1"
        >
          Duración (semanas)
        </label>
        <input
          id="plan-duration-weeks"
          type="number"
          name="duration_weeks"
          defaultValue={plan?.duration_weeks ?? ""}
          min={1}
          placeholder="Ej: 8"
          className="w-40 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        <p className="mt-1 text-xs text-gray-400">Opcional. Indica la duración total del plan.</p>
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="w-full bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors"
      >
        {isPending
          ? plan
            ? "Guardando..."
            : "Creando..."
          : plan
            ? "Guardar cambios"
            : "Crear plan"}
      </button>
    </form>
  );
}
