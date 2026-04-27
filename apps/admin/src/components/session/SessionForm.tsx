"use client";
import { useActionState } from "react";
import {
  createSessionAction,
  updateSessionAction,
  type SessionFormState,
} from "@/app/actions/session";

interface SessionData {
  id: string;
  name: string;
  description: string | null;
  rest_between_exercises_seconds: number;
}

interface Props {
  session?: SessionData;
}

export function SessionForm({ session }: Props) {
  const action = session ? updateSessionAction.bind(null, session.id) : createSessionAction;

  const [state, formAction, isPending] = useActionState<SessionFormState, FormData>(action, {});

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
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Nombre <span className="text-red-500">*</span>
        </label>
        <input
          type="text"
          name="name"
          defaultValue={session?.name}
          required
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        {state.error?.name && <p className="mt-1 text-xs text-red-600">{state.error.name[0]}</p>}
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">Descripción</label>
        <textarea
          name="description"
          defaultValue={session?.description ?? ""}
          rows={3}
          className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
          placeholder="Descripción opcional de la sesión..."
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Descanso entre ejercicios (segundos)
        </label>
        <input
          type="number"
          name="rest_between_exercises_seconds"
          defaultValue={session?.rest_between_exercises_seconds ?? 60}
          min={0}
          className="w-40 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="w-full bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors"
      >
        {isPending
          ? session
            ? "Guardando..."
            : "Creando..."
          : session
            ? "Guardar cambios"
            : "Crear sesión"}
      </button>
    </form>
  );
}
