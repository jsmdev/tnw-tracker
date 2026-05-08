import { describe, it, expect, vi, beforeEach } from "vitest";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireUser, requireOwnership, OwnershipError } from "@/lib/auth";

// -------------------------------------------------------------------
// Helpers para construir mocks de Supabase de forma legible
// -------------------------------------------------------------------

const mockUser = { id: "user-123", email: "test@test.com" };

function mockGetUser(user: typeof mockUser | null, error: null | { message: string } = null) {
  const client = {
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user }, error }),
    },
    from: vi.fn(),
  };
  vi.mocked(createClient).mockResolvedValue(client as never);
  return client;
}

function mockFromChain(result: { data: unknown; error: unknown }) {
  const chain = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    maybeSingle: vi.fn().mockResolvedValue(result),
  };
  return chain;
}

// -------------------------------------------------------------------
// requireUser
// -------------------------------------------------------------------

describe("requireUser", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("devuelve el user cuando getUser() retorna un user válido", async () => {
    const client = mockGetUser(mockUser);
    const result = await requireUser(client as never);
    expect(result).toEqual(mockUser);
  });

  it("llama a redirect('/login') cuando getUser() retorna user null", async () => {
    const client = mockGetUser(null);
    await expect(requireUser(client as never)).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });

  it("llama a redirect('/login') cuando getUser() retorna error de Supabase", async () => {
    const client = mockGetUser(null, { message: "JWT expired" });
    await expect(requireUser(client as never)).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });
});

// -------------------------------------------------------------------
// requireOwnership
// -------------------------------------------------------------------

describe("requireOwnership", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("no lanza error cuando el record existe y pertenece al user", async () => {
    const client = {
      auth: { getUser: vi.fn() },
      from: vi.fn(() => mockFromChain({ data: { id: "rec-1" }, error: null })),
    };
    vi.mocked(createClient).mockResolvedValue(client as never);

    await expect(
      requireOwnership(client as never, "exercises", "rec-1", "user-123")
    ).resolves.toBeUndefined();
  });

  it("lanza OwnershipError con table e id correctos cuando data es null", async () => {
    const client = {
      auth: { getUser: vi.fn() },
      from: vi.fn(() => mockFromChain({ data: null, error: null })),
    };
    vi.mocked(createClient).mockResolvedValue(client as never);

    await expect(
      requireOwnership(client as never, "plans", "plan-abc", "user-123")
    ).rejects.toThrow(OwnershipError);

    try {
      await requireOwnership(client as never, "plans", "plan-abc", "user-123");
    } catch (e) {
      expect(e).toBeInstanceOf(OwnershipError);
      expect((e as OwnershipError).table).toBe("plans");
      expect((e as OwnershipError).id).toBe("plan-abc");
    }
  });

  it("lanza OwnershipError cuando Supabase retorna un error", async () => {
    const client = {
      auth: { getUser: vi.fn() },
      from: vi.fn(() => mockFromChain({ data: null, error: { message: "DB error" } })),
    };
    vi.mocked(createClient).mockResolvedValue(client as never);

    await expect(
      requireOwnership(client as never, "sessions", "sess-1", "user-123")
    ).rejects.toThrow(OwnershipError);
  });

  it("usa la query JOIN de exercises para exercise_videos", async () => {
    const chain = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      maybeSingle: vi.fn().mockResolvedValue({ data: { id: "vid-1" }, error: null }),
    };
    const client = {
      auth: { getUser: vi.fn() },
      from: vi.fn(() => chain),
    };
    vi.mocked(createClient).mockResolvedValue(client as never);

    await expect(
      requireOwnership(client as never, "exercise_videos", "vid-1", "user-123")
    ).resolves.toBeUndefined();

    // Para exercise_videos, la query va sobre la tabla exercises (JOIN)
    expect(client.from).toHaveBeenCalledWith("exercises");
  });
});
