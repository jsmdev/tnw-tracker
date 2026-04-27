"use client";
import { useState, useTransition } from "react";
import { addRoutineToPlanAction } from "@/app/actions/plan";

interface RoutineOption {
  id: string;
  name: string;
}

interface Props {
  planId: string;
  routines: RoutineOption[];
}

export function RoutineCombobox({ planId, routines }: Props) {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const filtered =
    query.length > 0
      ? routines.filter((r) => r.name.toLowerCase().includes(query.toLowerCase())).slice(0, 8)
      : routines.slice(0, 8);

  function handleSelect(routine: RoutineOption) {
    setQuery("");
    setOpen(false);
    setError(null);
    startTransition(async () => {
      const result = await addRoutineToPlanAction(planId, routine.id);
      if (result.error) setError(result.error);
    });
  }

  return (
    <div className="relative">
      <div className="flex gap-2">
        <input
          type="text"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onBlur={() => setTimeout(() => setOpen(false), 150)}
          placeholder="Buscar rutina por nombre..."
          disabled={isPending}
          className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50"
        />
        {isPending && <span className="self-center text-xs text-gray-400">Añadiendo...</span>}
      </div>

      {open && filtered.length > 0 && (
        <ul className="absolute z-10 mt-1 w-full bg-white border border-gray-200 rounded-lg shadow-lg max-h-60 overflow-auto">
          {filtered.map((r) => (
            <li key={r.id}>
              <button
                type="button"
                onMouseDown={() => handleSelect(r)}
                className="w-full text-left px-4 py-2.5 hover:bg-gray-50 text-sm font-medium text-gray-900"
              >
                {r.name}
              </button>
            </li>
          ))}
        </ul>
      )}

      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
    </div>
  );
}
