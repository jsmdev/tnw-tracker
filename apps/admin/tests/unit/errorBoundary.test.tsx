import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import DashboardError from "@/app/(app)/dashboard/error";

describe("DashboardError (error.tsx)", () => {
  it("renderiza el mensaje 'Algo salió mal'", () => {
    const error = new Error("Error de prueba");
    const reset = vi.fn();
    render(<DashboardError error={error} reset={reset} />);
    expect(screen.getByText("Algo salió mal")).toBeInTheDocument();
  });

  it("el botón 'Reintentar' llama a reset() al hacer click", () => {
    const error = new Error("Error de prueba");
    const reset = vi.fn();
    render(<DashboardError error={error} reset={reset} />);
    const button = screen.getByRole("button", { name: "Reintentar" });
    fireEvent.click(button);
    expect(reset).toHaveBeenCalledTimes(1);
  });
});
