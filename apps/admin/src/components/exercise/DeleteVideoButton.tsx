"use client";
import { useState, useTransition } from "react";
import { deleteExerciseVideoAction } from "@/app/actions/exercise";

interface Props {
  videoId: string;
  exerciseId: string;
}

export function DeleteVideoButton({ videoId, exerciseId }: Props) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  function handleClick() {
    setError(null);
    startTransition(async () => {
      const result = await deleteExerciseVideoAction(videoId, exerciseId);
      if (result?.error) setError(result.error);
    });
  }

  return (
    <div className="ml-4 shrink-0 flex flex-col items-end gap-1">
      <button
        type="button"
        onClick={handleClick}
        disabled={isPending}
        className="text-red-500 hover:text-red-700 text-sm font-medium disabled:opacity-50"
      >
        {isPending ? "Eliminando…" : "Eliminar"}
      </button>
      {error && (
        <p role="alert" className="text-xs text-red-600">
          {error}
        </p>
      )}
    </div>
  );
}
