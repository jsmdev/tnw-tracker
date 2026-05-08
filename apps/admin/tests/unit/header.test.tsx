import { render, screen } from "@testing-library/react";
import type { User } from "@supabase/supabase-js";
import { describe, it, expect, vi } from "vitest";

// LogoutButton es "use client" y usa @/lib/supabase/client — mockear para tests
vi.mock("@/lib/supabase/client", () => ({
  createClient: vi.fn(() => ({
    auth: {
      signOut: vi.fn().mockResolvedValue({}),
    },
  })),
}));

// Mock LogoutButton para aislar el test del Header
// (Server Component no puede importar Client Component con hooks en jsdom sin wrapper)
vi.mock("@/components/LogoutButton", () => ({
  LogoutButton: () => <button type="button">Cerrar sesión</button>,
}));

import { Header } from "@/components/Header";

describe("Header", () => {
  it("renderiza el email del usuario en el DOM", () => {
    const user = { email: "test@test.com" } as User;
    render(<Header user={user} />);
    expect(screen.getByText("test@test.com")).toBeInTheDocument();
  });

  it("renderiza el LogoutButton con texto 'Cerrar sesión'", () => {
    const user = { email: "admin@example.com" } as User;
    render(<Header user={user} />);
    expect(screen.getByRole("button", { name: "Cerrar sesión" })).toBeInTheDocument();
  });
});
