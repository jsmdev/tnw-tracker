import { describe, it, expect, vi, beforeEach } from "vitest";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import {
  createSessionAction,
  updateSessionAction,
  deleteSessionAction,
  reorderSessionExercisesAction,
  addExerciseToSessionAction,
  removeExerciseFromSessionAction,
} from "@/app/actions/session";

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const mockUser = { id: "user-123", email: "test@test.com" };

type Result = { data: unknown; error: unknown };

interface ClientOpts {
  user?: typeof mockUser | null;
  results?: {
    insertSelectSingle?: Result;
    updateChain?: Result;
    ownership?: Result;
    maybeSingleSequence?: Result[];
    insertOnly?: Result;
    deleteChain?: Result;
    rpc?: Result;
  };
}

function makeClient(opts: ClientOpts = {}) {
  const r = opts.results ?? {};
  const ok: Result = { data: null, error: null };

  const maybeSingleMock = vi.fn();
  if (r.maybeSingleSequence) {
    for (const v of r.maybeSingleSequence) maybeSingleMock.mockResolvedValueOnce(v);
    maybeSingleMock.mockResolvedValue(ok);
  } else {
    maybeSingleMock.mockResolvedValue(r.ownership ?? ok);
  }

  const chain = {
    select: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    maybeSingle: maybeSingleMock,
    single: vi.fn().mockResolvedValue(r.insertSelectSingle ?? ok),
    update: vi.fn().mockReturnThis(),
    delete: vi.fn().mockReturnThis(),

    insert: vi.fn().mockImplementation(function () {
      const result = r.insertOnly ?? ok;
      return {
        ...chain,
        then: (onF?: (v: Result) => unknown, onR?: (e: unknown) => unknown) =>
          Promise.resolve(result).then(onF, onR),
      };
    }),

    eq: vi.fn().mockImplementation(function () {
      const upd = chain.update as { mock: { calls: unknown[] } };
      const del = chain.delete as { mock: { calls: unknown[] } };
      let result: Result = ok;
      if (del.mock.calls.length > 0) result = r.deleteChain ?? ok;
      else if (upd.mock.calls.length > 0) result = r.updateChain ?? ok;

      return {
        ...chain,
        then: (onF?: (v: Result) => unknown, onR?: (e: unknown) => unknown) =>
          Promise.resolve(result).then(onF, onR),
      };
    }),
  };

  const client = {
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: opts.user === undefined ? mockUser : opts.user },
        error: null,
      }),
    },
    from: vi.fn(() => chain),
    rpc: vi.fn().mockResolvedValue(r.rpc ?? ok),
  };
  vi.mocked(createClient).mockResolvedValue(client as never);
  return { client, chain };
}

function formDataOf(fields: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
}

const VALID_SESSION = { name: "Push A", rest_between_exercises_seconds: "90" };

// =====================================================================
// createSessionAction
// =====================================================================

describe("createSessionAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: inserts and redirects to the new session", async () => {
    const { client, chain } = makeClient({
      results: { insertSelectSingle: { data: { id: "se-new" }, error: null } },
    });

    await expect(createSessionAction({}, formDataOf(VALID_SESSION))).rejects.toThrow("REDIRECT");

    expect(client.from).toHaveBeenCalledWith("sessions");
    expect(chain.insert).toHaveBeenCalledWith({
      user_id: mockUser.id,
      name: "Push A",
      description: null,
      rest_between_exercises_seconds: 90,
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/sessions");
    expect(redirect).toHaveBeenCalledWith("/dashboard/sessions/se-new");
  });

  it("defaults rest_between_exercises_seconds to 60 when missing/zero", async () => {
    const { chain } = makeClient({
      results: { insertSelectSingle: { data: { id: "se-new" }, error: null } },
    });

    await expect(createSessionAction({}, formDataOf({ name: "X" }))).rejects.toThrow("REDIRECT");

    expect(chain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ rest_between_exercises_seconds: 60 })
    );
  });

  it("passes description when present", async () => {
    const { chain } = makeClient({
      results: { insertSelectSingle: { data: { id: "se-new" }, error: null } },
    });

    await expect(
      createSessionAction({}, formDataOf({ ...VALID_SESSION, description: "Heavy day" }))
    ).rejects.toThrow("REDIRECT");

    expect(chain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ description: "Heavy day" })
    );
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(createSessionAction({}, formDataOf(VALID_SESSION))).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });

  it("returns field errors when name is empty", async () => {
    const { chain } = makeClient();
    const result = await createSessionAction({}, formDataOf({ name: "" }));
    expect(result.error?.name).toBeDefined();
    expect(chain.insert).not.toHaveBeenCalled();
  });

  it("returns the DB error message when insert fails", async () => {
    makeClient({
      results: { insertSelectSingle: { data: null, error: { message: "unique violation" } } },
    });
    const result = await createSessionAction({}, formDataOf(VALID_SESSION));
    expect(result.message).toBe("unique violation");
    expect(redirect).not.toHaveBeenCalled();
  });
});

// =====================================================================
// updateSessionAction
// =====================================================================

describe("updateSessionAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: updates scoped to (id, user_id) and revalidates both paths", async () => {
    const { chain } = makeClient();
    const result = await updateSessionAction("se-1", {}, formDataOf(VALID_SESSION));

    expect(result).toEqual({ message: "Sesión actualizada correctamente" });
    expect(chain.update).toHaveBeenCalledWith({
      name: "Push A",
      description: null,
      rest_between_exercises_seconds: 90,
    });
    expect(chain.eq).toHaveBeenNthCalledWith(1, "id", "se-1");
    expect(chain.eq).toHaveBeenNthCalledWith(2, "user_id", mockUser.id);
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/sessions");
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/sessions/se-1");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(updateSessionAction("se-1", {}, formDataOf(VALID_SESSION))).rejects.toThrow(
      "REDIRECT"
    );
  });

  it("returns field errors for invalid input", async () => {
    const { chain } = makeClient();
    const result = await updateSessionAction("se-1", {}, formDataOf({ name: "" }));
    expect(result.error?.name).toBeDefined();
    expect(chain.update).not.toHaveBeenCalled();
  });

  it("returns the DB error message when update fails", async () => {
    makeClient({ results: { updateChain: { data: null, error: { message: "denied" } } } });
    const result = await updateSessionAction("se-1", {}, formDataOf(VALID_SESSION));
    expect(result.message).toBe("denied");
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});

// =====================================================================
// deleteSessionAction (HARD delete — distinct from plans/routines/exercises)
// =====================================================================

describe("deleteSessionAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("hard-deletes scoped to (id, user_id) and redirects to the list", async () => {
    const { client, chain } = makeClient();
    await expect(deleteSessionAction("se-1")).rejects.toThrow("REDIRECT");

    expect(client.from).toHaveBeenCalledWith("sessions");
    // Sessions are hard-deleted (no is_active flag) — sanity check vs. plans/routines/exercises
    expect(chain.delete).toHaveBeenCalled();
    expect(chain.update).not.toHaveBeenCalled();
    expect(chain.eq).toHaveBeenNthCalledWith(1, "id", "se-1");
    expect(chain.eq).toHaveBeenNthCalledWith(2, "user_id", mockUser.id);
    expect(redirect).toHaveBeenCalledWith("/dashboard/sessions");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(deleteSessionAction("se-1")).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });
});

// =====================================================================
// reorderSessionExercisesAction
// =====================================================================

describe("reorderSessionExercisesAction", () => {
  beforeEach(() => vi.clearAllMocks());

  const SE_1 = "11111111-1111-4111-8111-111111111111";
  const SE_2 = "22222222-2222-4222-8222-222222222222";
  const ITEMS = [
    { id: SE_1, orderIndex: 0 },
    { id: SE_2, orderIndex: 1 },
  ];

  it("happy path: calls rpc('reorder_items') with snake_case payload and revalidates", async () => {
    const { client } = makeClient({
      results: { ownership: { data: { id: "se-1" }, error: null } },
    });

    const result = await reorderSessionExercisesAction("se-1", ITEMS);

    expect(result).toEqual({});
    expect(client.rpc).toHaveBeenCalledWith("reorder_items", {
      p_table: "session_exercises",
      p_parent_col: "session_id",
      p_parent_id: "se-1",
      p_items: [
        { id: SE_1, order_index: 0 },
        { id: SE_2, order_index: 1 },
      ],
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/sessions/se-1");
  });

  it("returns 'Datos inválidos' when the items array is invalid", async () => {
    const { client } = makeClient();
    // @ts-expect-error — intentionally bad shape
    const result = await reorderSessionExercisesAction("se-1", [{ id: "x" }]);
    expect(result).toEqual({ error: "Datos inválidos" });
    expect(client.rpc).not.toHaveBeenCalled();
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(reorderSessionExercisesAction("se-1", ITEMS)).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the session does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await reorderSessionExercisesAction("se-1", ITEMS);
    expect(result).toEqual({ error: "No autorizado" });
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("maps RPC error 'unauthorized' to 'No autorizado'", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "se-1" }, error: null },
        rpc: { data: null, error: { message: "unauthorized" } },
      },
    });
    const result = await reorderSessionExercisesAction("se-1", ITEMS);
    expect(result).toEqual({ error: "No autorizado" });
  });

  it("maps RPC error 'invalid_table' to 'Datos inválidos'", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "se-1" }, error: null },
        rpc: { data: null, error: { message: "invalid_table" } },
      },
    });
    const result = await reorderSessionExercisesAction("se-1", ITEMS);
    expect(result).toEqual({ error: "Datos inválidos" });
  });

  it("falls through to the raw RPC error message for unknown errors", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "se-1" }, error: null },
        rpc: { data: null, error: { message: "deadlock detected" } },
      },
    });
    const result = await reorderSessionExercisesAction("se-1", ITEMS);
    expect(result).toEqual({ error: "deadlock detected" });
  });
});

// =====================================================================
// addExerciseToSessionAction
// =====================================================================

describe("addExerciseToSessionAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path with no existing items: inserts at order_index 0", async () => {
    const { client, chain } = makeClient({
      results: {
        maybeSingleSequence: [
          { data: { id: "se-1" }, error: null },
          { data: null, error: null },
        ],
      },
    });

    const result = await addExerciseToSessionAction("se-1", "ex-1");
    expect(result).toEqual({});
    expect(client.from).toHaveBeenCalledWith("session_exercises");
    expect(chain.insert).toHaveBeenCalledWith({
      session_id: "se-1",
      exercise_id: "ex-1",
      order_index: 0,
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/sessions/se-1");
  });

  it("happy path with existing items: inserts at last.order_index + 1", async () => {
    const { chain } = makeClient({
      results: {
        maybeSingleSequence: [
          { data: { id: "se-1" }, error: null },
          { data: { order_index: 6 }, error: null },
        ],
      },
    });

    await addExerciseToSessionAction("se-1", "ex-1");
    expect(chain.insert).toHaveBeenCalledWith(expect.objectContaining({ order_index: 7 }));
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(addExerciseToSessionAction("se-1", "ex-1")).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the session does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await addExerciseToSessionAction("se-1", "ex-1");
    expect(result).toEqual({ error: "No autorizado" });
  });

  it("returns the insert error when Supabase fails", async () => {
    makeClient({
      results: {
        maybeSingleSequence: [
          { data: { id: "se-1" }, error: null },
          { data: null, error: null },
        ],
        insertOnly: { data: null, error: { message: "FK violation" } },
      },
    });
    const result = await addExerciseToSessionAction("se-1", "ex-1");
    expect(result).toEqual({ error: "FK violation" });
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});

// =====================================================================
// removeExerciseFromSessionAction
// =====================================================================

describe("removeExerciseFromSessionAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: deletes the junction row and returns {}", async () => {
    const { client, chain } = makeClient({
      results: { ownership: { data: { id: "se-1" }, error: null } },
    });

    const result = await removeExerciseFromSessionAction("sex-1", "se-1");

    expect(result).toEqual({});
    expect(client.from).toHaveBeenCalledWith("session_exercises");
    expect(chain.delete).toHaveBeenCalled();
    expect(chain.eq).toHaveBeenCalledWith("id", "sex-1");
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/sessions/se-1");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(removeExerciseFromSessionAction("sex-1", "se-1")).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the session does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await removeExerciseFromSessionAction("sex-1", "se-1");
    expect(result).toEqual({ error: "No autorizado" });
  });

  it("returns the delete error when Supabase fails", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "se-1" }, error: null },
        deleteChain: { data: null, error: { message: "constraint" } },
      },
    });
    const result = await removeExerciseFromSessionAction("sex-1", "se-1");
    expect(result).toEqual({ error: "constraint" });
  });
});
