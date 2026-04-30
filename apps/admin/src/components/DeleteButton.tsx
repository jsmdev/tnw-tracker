"use client";

interface DeleteButtonProps {
  action: () => Promise<void>;
  confirmMessage: string;
}

export function DeleteButton({ action, confirmMessage }: DeleteButtonProps) {
  return (
    <form
      action={action}
      onSubmit={(ev) => {
        if (!confirm(confirmMessage)) ev.preventDefault();
      }}
      className="inline"
    >
      <button type="submit" className="text-red-500 hover:text-red-700 font-medium">
        Eliminar
      </button>
    </form>
  );
}
