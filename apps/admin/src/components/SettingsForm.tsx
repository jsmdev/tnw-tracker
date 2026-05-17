"use client";

import { useActionState } from "react";
import { updateSettingsAction, type SettingsFormState } from "@/app/actions/settings";

interface Props {
  weightUnit: "kg" | "lb";
  timerTriggerMode: "auto" | "manual";
}

const initial: SettingsFormState = {};

export function SettingsForm({ weightUnit, timerTriggerMode }: Props) {
  const [state, formAction, isPending] = useActionState(updateSettingsAction, initial);

  return (
    <form action={formAction} className="space-y-6">
      <div>
        <label
          htmlFor="settings-weight-unit"
          className="block text-sm font-medium text-gray-700 mb-1"
        >
          Unidad de peso
        </label>
        <select
          id="settings-weight-unit"
          name="weight_unit"
          defaultValue={weightUnit}
          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="kg">kg</option>
          <option value="lb">lb</option>
        </select>
        {state.error?.weight_unit && (
          <p className="mt-1 text-xs text-red-600">{state.error.weight_unit[0]}</p>
        )}
      </div>

      <div>
        <label
          htmlFor="settings-timer-trigger-mode"
          className="block text-sm font-medium text-gray-700 mb-1"
        >
          Modo de timer
        </label>
        <select
          id="settings-timer-trigger-mode"
          name="timer_trigger_mode"
          defaultValue={timerTriggerMode}
          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="auto">Automático (se inicia al guardar serie)</option>
          <option value="manual">Manual (se inicia con botón)</option>
        </select>
        {state.error?.timer_trigger_mode && (
          <p className="mt-1 text-xs text-red-600">{state.error.timer_trigger_mode[0]}</p>
        )}
      </div>

      {state.message && (
        <p className={`text-sm ${state.success ? "text-green-600" : "text-red-600"}`}>
          {state.message}
        </p>
      )}

      <button
        type="submit"
        disabled={isPending}
        className="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg text-sm transition-colors disabled:opacity-50"
      >
        {isPending ? "Guardando…" : "Guardar ajustes"}
      </button>
    </form>
  );
}
