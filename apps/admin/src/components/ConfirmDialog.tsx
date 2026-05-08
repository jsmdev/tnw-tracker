"use client";

import { useRef, useState, useTransition, useId } from "react";

interface ConfirmDialogProps {
  triggerLabel: string;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  action: () => Promise<{ error?: string } | void>;
  triggerClassName?: string;
}

export function ConfirmDialog({
  triggerLabel,
  title,
  message,
  confirmLabel = "Confirmar",
  cancelLabel = "Cancelar",
  action,
  triggerClassName,
}: ConfirmDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const baseId = useId();
  const titleId = `${baseId}-title`;
  const messageId = `${baseId}-message`;

  function handleOpen() {
    setError(null);
    dialogRef.current?.showModal();
  }

  function handleConfirm() {
    startTransition(async () => {
      const result = await action();
      if (result?.error) {
        setError(result.error);
      } else {
        dialogRef.current?.close();
      }
    });
  }

  return (
    <>
      <button
        type="button"
        onClick={handleOpen}
        className={triggerClassName ?? "text-red-500 hover:text-red-700 font-medium"}
      >
        {triggerLabel}
      </button>

      <dialog
        ref={dialogRef}
        aria-labelledby={titleId}
        aria-describedby={messageId}
        className="rounded-xl shadow-lg p-6 w-full max-w-md backdrop:bg-black/40 open:flex open:flex-col open:gap-4"
      >
        <h2 id={titleId} className="text-lg font-semibold text-gray-900">
          {title}
        </h2>
        <p id={messageId} className="text-sm text-gray-600">
          {message}
        </p>

        {error && (
          <p role="alert" className="text-red-600 text-sm">
            {error}
          </p>
        )}

        <div className="flex justify-end gap-3 mt-2">
          <form method="dialog">
            <button
              type="submit"
              className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
            >
              {cancelLabel}
            </button>
          </form>
          <button
            type="button"
            onClick={handleConfirm}
            disabled={isPending}
            className="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {isPending ? "Eliminando…" : confirmLabel}
          </button>
        </div>
      </dialog>
    </>
  );
}
