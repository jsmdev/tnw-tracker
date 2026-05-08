import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { ConfirmDialog } from "@/components/ConfirmDialog";

// jsdom no implementa <dialog> nativo — se mockean showModal y close
beforeEach(() => {
  HTMLDialogElement.prototype.showModal = vi.fn();
  HTMLDialogElement.prototype.close = vi.fn();
});

describe("ConfirmDialog", () => {
  const defaultProps = {
    triggerLabel: "Eliminar",
    title: "Eliminar ejercicio",
    message: '¿Seguro que deseas eliminar "Press banca"?',
    action: vi.fn().mockResolvedValue(undefined),
  };

  it("1. Renderiza el botón trigger con triggerLabel", () => {
    render(<ConfirmDialog {...defaultProps} />);
    expect(screen.getByRole("button", { name: "Eliminar" })).toBeInTheDocument();
  });

  it("2. Click en trigger llama showModal()", () => {
    render(<ConfirmDialog {...defaultProps} />);
    const trigger = screen.getByRole("button", { name: "Eliminar" });
    fireEvent.click(trigger);
    expect(HTMLDialogElement.prototype.showModal).toHaveBeenCalledTimes(1);
  });

  it("3. Click en Cancelar no llama action", () => {
    const action = vi.fn().mockResolvedValue(undefined);
    render(<ConfirmDialog {...defaultProps} action={action} />);
    // Abrir el modal primero (simula comportamiento real del usuario)
    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    const cancelBtn = screen.getByRole("button", { name: /cancelar/i, hidden: true });
    fireEvent.click(cancelBtn);
    expect(action).not.toHaveBeenCalled();
  });

  it("4. Click en Confirmar invoca action; botón Confirmar queda disabled mientras isPending", async () => {
    let resolveAction!: () => void;
    const action = vi.fn(
      () =>
        new Promise<void>((resolve) => {
          resolveAction = resolve;
        })
    );
    render(<ConfirmDialog {...defaultProps} action={action} />);
    // Abrir el modal primero
    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    const confirmBtn = screen.getByRole("button", { name: /confirmar/i, hidden: true });

    fireEvent.click(confirmBtn);
    // La action se invocó
    expect(action).toHaveBeenCalledTimes(1);
    // Mientras está pendiente, el botón debe estar disabled
    await waitFor(() => {
      expect(screen.getByRole("button", { name: /eliminando/i, hidden: true })).toBeDisabled();
    });
    resolveAction();
  });

  it("5. Cuando action devuelve { error }, el error es visible y el modal no se cierra", async () => {
    const action = vi.fn().mockResolvedValue({ error: "Error de prueba" });
    render(<ConfirmDialog {...defaultProps} action={action} />);
    // Abrir el modal primero
    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    const confirmBtn = screen.getByRole("button", { name: /confirmar/i, hidden: true });

    fireEvent.click(confirmBtn);
    await waitFor(() => {
      // { hidden: true } porque el <dialog> sin open es "hidden" en jsdom
      expect(screen.getByRole("alert", { hidden: true })).toBeInTheDocument();
      expect(screen.getByRole("alert", { hidden: true })).toHaveTextContent("Error de prueba");
    });
    // close() no debe haberse llamado
    expect(HTMLDialogElement.prototype.close).not.toHaveBeenCalled();
  });

  it("6. Cuando action resuelve sin error, close() es llamado", async () => {
    const action = vi.fn().mockResolvedValue(undefined);
    render(<ConfirmDialog {...defaultProps} action={action} />);
    // Abrir el modal primero
    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    const confirmBtn = screen.getByRole("button", { name: /confirmar/i, hidden: true });

    fireEvent.click(confirmBtn);
    await waitFor(() => {
      expect(HTMLDialogElement.prototype.close).toHaveBeenCalledTimes(1);
    });
  });

  it("7. <dialog> tiene aria-labelledby y aria-describedby apuntando a IDs presentes", () => {
    render(<ConfirmDialog {...defaultProps} />);
    const dialog = document.querySelector("dialog")!;
    const labelledById = dialog.getAttribute("aria-labelledby");
    const describedById = dialog.getAttribute("aria-describedby");

    expect(labelledById).toBeTruthy();
    expect(describedById).toBeTruthy();
    expect(document.getElementById(labelledById!)).toBeInTheDocument();
    expect(document.getElementById(describedById!)).toBeInTheDocument();
  });

  it("8. Evento cancel del dialog no llama action", async () => {
    const action = vi.fn().mockResolvedValue(undefined);
    render(<ConfirmDialog {...defaultProps} action={action} />);
    const dialog = document.querySelector("dialog")!;

    fireEvent(dialog, new Event("cancel"));
    expect(action).not.toHaveBeenCalled();
  });

  it("9. Doble click en Confirmar mientras pending solo llama action una vez", async () => {
    let resolveAction!: () => void;
    const action = vi.fn(
      () =>
        new Promise<void>((resolve) => {
          resolveAction = resolve;
        })
    );
    render(<ConfirmDialog {...defaultProps} action={action} />);
    // Abrir el modal primero
    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    const confirmBtn = screen.getByRole("button", { name: /confirmar/i, hidden: true });

    fireEvent.click(confirmBtn);
    // Esperar a que quede disabled (isPending = true)
    await waitFor(() => {
      expect(screen.getByRole("button", { name: /eliminando/i, hidden: true })).toBeDisabled();
    });
    // Segundo click sobre el botón disabled (no debe disparar nada)
    const disabledBtn = screen.getByRole("button", { name: /eliminando/i, hidden: true });
    fireEvent.click(disabledBtn);
    resolveAction();
    await waitFor(() => {
      expect(action).toHaveBeenCalledTimes(1);
    });
  });
});
