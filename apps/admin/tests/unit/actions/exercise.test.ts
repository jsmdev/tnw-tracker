import { describe, it, expect, vi, beforeEach } from "vitest";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import {
  createExerciseAction,
  updateExerciseAction,
  deleteExerciseAction,
  createExerciseVideoAction,
  deleteExerciseVideoAction,
} from "@/app/actions/exercise";

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const mockUser = { id: "user-123", email: "test@test.com" };

type Result = { data: unknown; error: unknown };

/**
 * Builds a Supabase client mock whose `from()` always returns the same
 * chain. Each chain method records its calls so tests can assert args.
 *
 * The chain supports all the operation shapes used across the exercise
 * actions:
 *   - insert(...).select(...).single() — createExercise
 *   - update(...).eq(...).eq(...)      — updateExercise / deleteExercise
 *   - select(...).eq(...).eq(...).maybeSingle() — requireOwnership
 *   - insert(...)                       — createExerciseVideo
 *   - delete().eq(...)                  — deleteExerciseVideo
 *
 * The terminal value depends on which method finally awaits — controlled
 * via the optional `results` object (any subset).
 */
interface ClientOpts {
  user?: typeof mockUser | null;
  results?: {
    /** terminal of insert().select().single() in createExercise */
    insertSelectSingle?: Result;
    /** terminal of update().eq().eq() chain */
    updateChain?: Result;
    /** terminal of select().eq().eq().maybeSingle() — used by requireOwnership */
    ownership?: Result;
    /** terminal of plain insert() (no .select chain) */
    insertOnly?: Result;
    /** terminal of delete().eq() chain */
    deleteChain?: Result;
  };
}

function makeClient(opts: ClientOpts = {}) {
  const r = opts.results ?? {};
  const ok: Result = { data: null, error: null };

  // `single()` and `eq()` (when terminal) are the two terminations we use.
  // We make `eq()` thenable — chaining still returns `this`, but awaiting
  // resolves to the right result depending on which operation kicked it off.
  const chain = {
    // SELECT path (used by requireOwnership)
    select: vi.fn().mockReturnThis(),
    maybeSingle: vi.fn().mockResolvedValue(r.ownership ?? ok),

    // INSERT paths
    insert: vi.fn().mockImplementation(function insertImpl(this: unknown) {
      // Returning a chain-shaped thenable lets `await insert(...)` resolve
      // to insertOnly while `await insert(...).select().single()` resolves
      // to insertSelectSingle.
      const result = r.insertOnly ?? ok;
      const thenable = {
        ...chain,
        then: (onFulfilled?: (v: Result) => unknown, onRejected?: (e: unknown) => unknown) =>
          Promise.resolve(result).then(onFulfilled, onRejected),
      };
      return thenable;
    }),
    single: vi.fn().mockResolvedValue(r.insertSelectSingle ?? ok),

    // UPDATE path
    update: vi.fn().mockReturnThis(),

    // DELETE path
    delete: vi.fn().mockReturnThis(),

    // eq() is the trickiest — it's used both as a non-terminal pass-through
    // (after update/select) and as the terminal awaitable (after the second
    // eq() in update().eq().eq() or after delete().eq()). We model it as a
    // thenable: chainable AND awaitable.
    eq: vi.fn().mockImplementation(function eqImpl(this: unknown) {
      // The terminal result depends on what method kicked off the chain.
      // We pick by checking which mocks were invoked.
      const upd = chain.update as { mock: { calls: unknown[] } };
      const del = chain.delete as { mock: { calls: unknown[] } };

      let result: Result = ok;
      if (del.mock.calls.length > 0) result = r.deleteChain ?? ok;
      else if (upd.mock.calls.length > 0) result = r.updateChain ?? ok;

      const thenable = {
        ...chain,
        then: (onFulfilled?: (v: Result) => unknown, onRejected?: (e: unknown) => unknown) =>
          Promise.resolve(result).then(onFulfilled, onRejected),
      };
      return thenable;
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
  };
  vi.mocked(createClient).mockResolvedValue(client as never);
  return { client, chain };
}

function formDataOf(fields: Record<string, string | string[]>): FormData {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) {
    if (Array.isArray(v)) v.forEach((x) => fd.append(k, x));
    else fd.append(k, v);
  }
  return fd;
}

const VALID_FORM = {
  name: "Bench Press",
  category: "Push",
  muscle_groups: ["chest", "triceps"],
};

// =====================================================================
// createExerciseAction
// =====================================================================

describe("createExerciseAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: inserts and redirects to the new exercise detail page", async () => {
    const { client, chain } = makeClient({
      results: { insertSelectSingle: { data: { id: "ex-new" }, error: null } },
    });

    await expect(createExerciseAction({}, formDataOf(VALID_FORM))).rejects.toThrow("REDIRECT");

    expect(client.from).toHaveBeenCalledWith("exercises");
    expect(chain.insert).toHaveBeenCalledWith({
      user_id: mockUser.id,
      name: "Bench Press",
      category: "Push",
      muscle_groups: ["chest", "triceps"],
      instructions: null,
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/exercises");
    expect(redirect).toHaveBeenCalledWith("/dashboard/exercises/ex-new");
  });

  it("passes instructions when present in the form", async () => {
    const { chain } = makeClient({
      results: { insertSelectSingle: { data: { id: "ex-new" }, error: null } },
    });

    await expect(
      createExerciseAction({}, formDataOf({ ...VALID_FORM, instructions: "Keep elbows tucked" }))
    ).rejects.toThrow("REDIRECT");

    expect(chain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ instructions: "Keep elbows tucked" })
    );
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(createExerciseAction({}, formDataOf(VALID_FORM))).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });

  it("returns field errors when name is empty", async () => {
    const { chain } = makeClient();
    const result = await createExerciseAction({}, formDataOf({ ...VALID_FORM, name: "" }));
    expect(result.error?.name).toBeDefined();
    expect(chain.insert).not.toHaveBeenCalled();
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("returns field errors when muscle_groups is empty", async () => {
    const { chain } = makeClient();
    const result = await createExerciseAction(
      {},
      formDataOf({ name: "X", category: "Push", muscle_groups: [] })
    );
    expect(result.error?.muscle_groups).toBeDefined();
    expect(chain.insert).not.toHaveBeenCalled();
  });

  it("returns field errors when category is invalid", async () => {
    const { chain } = makeClient();
    const result = await createExerciseAction(
      {},
      formDataOf({ ...VALID_FORM, category: "Stretching" })
    );
    expect(result.error?.category).toBeDefined();
    expect(chain.insert).not.toHaveBeenCalled();
  });

  it("returns the DB error message when insert fails", async () => {
    makeClient({
      results: { insertSelectSingle: { data: null, error: { message: "duplicate key value" } } },
    });
    const result = await createExerciseAction({}, formDataOf(VALID_FORM));
    expect(result.message).toBe("duplicate key value");
    expect(revalidatePath).not.toHaveBeenCalled();
    expect(redirect).not.toHaveBeenCalled();
  });
});

// =====================================================================
// updateExerciseAction
// =====================================================================

describe("updateExerciseAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: updates the row scoped to (id, user_id) and revalidates both paths", async () => {
    const { client, chain } = makeClient();
    const result = await updateExerciseAction("ex-1", {}, formDataOf(VALID_FORM));

    expect(result).toEqual({ message: "Ejercicio actualizado correctamente" });
    expect(client.from).toHaveBeenCalledWith("exercises");
    expect(chain.update).toHaveBeenCalledWith({
      name: "Bench Press",
      category: "Push",
      muscle_groups: ["chest", "triceps"],
      instructions: null,
    });
    expect(chain.eq).toHaveBeenNthCalledWith(1, "id", "ex-1");
    expect(chain.eq).toHaveBeenNthCalledWith(2, "user_id", mockUser.id);
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/exercises");
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/exercises/ex-1");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(updateExerciseAction("ex-1", {}, formDataOf(VALID_FORM))).rejects.toThrow(
      "REDIRECT"
    );
    expect(redirect).toHaveBeenCalledWith("/login");
  });

  it("returns field errors for invalid input", async () => {
    const { chain } = makeClient();
    const result = await updateExerciseAction("ex-1", {}, formDataOf({ ...VALID_FORM, name: "" }));
    expect(result.error?.name).toBeDefined();
    expect(chain.update).not.toHaveBeenCalled();
  });

  it("returns the DB error message when update fails", async () => {
    makeClient({
      results: { updateChain: { data: null, error: { message: "permission denied" } } },
    });
    const result = await updateExerciseAction("ex-1", {}, formDataOf(VALID_FORM));
    expect(result.message).toBe("permission denied");
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});

// =====================================================================
// deleteExerciseAction
// =====================================================================

describe("deleteExerciseAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("soft-deletes (sets is_active=false), scoped to (id, user_id), and redirects to the list", async () => {
    const { client, chain } = makeClient();

    await expect(deleteExerciseAction("ex-1")).rejects.toThrow("REDIRECT");

    expect(client.from).toHaveBeenCalledWith("exercises");
    expect(chain.update).toHaveBeenCalledWith({ is_active: false });
    expect(chain.eq).toHaveBeenNthCalledWith(1, "id", "ex-1");
    expect(chain.eq).toHaveBeenNthCalledWith(2, "user_id", mockUser.id);
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/exercises");
    expect(redirect).toHaveBeenCalledWith("/dashboard/exercises");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(deleteExerciseAction("ex-1")).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });
});

// =====================================================================
// createExerciseVideoAction
// =====================================================================

describe("createExerciseVideoAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: inserts a video and returns {}", async () => {
    const { client, chain } = makeClient({
      results: { ownership: { data: { id: "ex-1" }, error: null } },
    });

    const result = await createExerciseVideoAction("ex-1", "https://youtu.be/abc", "youtube");

    expect(result).toEqual({});
    expect(client.from).toHaveBeenCalledWith("exercise_videos");
    expect(chain.insert).toHaveBeenCalledWith({
      exercise_id: "ex-1",
      source: "youtube",
      url: "https://youtu.be/abc",
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/exercises/ex-1");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(
      createExerciseVideoAction("ex-1", "https://youtu.be/abc", "youtube")
    ).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the exercise does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await createExerciseVideoAction("ex-1", "https://youtu.be/abc", "youtube");
    expect(result).toEqual({ error: "No autorizado" });
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("returns the insert error when Supabase fails", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "ex-1" }, error: null },
        insertOnly: { data: null, error: { message: "constraint violation" } },
      },
    });
    const result = await createExerciseVideoAction("ex-1", "https://youtu.be/abc", "youtube");
    expect(result.error).toBe("constraint violation");
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});

// =====================================================================
// deleteExerciseVideoAction
// =====================================================================

describe("deleteExerciseVideoAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: deletes the video by id and returns {}", async () => {
    const { client, chain } = makeClient({
      results: { ownership: { data: { id: "ex-1" }, error: null } },
    });

    const result = await deleteExerciseVideoAction("vid-1", "ex-1");

    expect(result).toEqual({});
    expect(client.from).toHaveBeenCalledWith("exercise_videos");
    expect(chain.delete).toHaveBeenCalled();
    expect(chain.eq).toHaveBeenCalledWith("id", "vid-1");
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/exercises/ex-1");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(deleteExerciseVideoAction("vid-1", "ex-1")).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the exercise does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await deleteExerciseVideoAction("vid-1", "ex-1");
    expect(result).toEqual({ error: "No autorizado" });
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("returns the delete error when Supabase fails", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "ex-1" }, error: null },
        deleteChain: { data: null, error: { message: "FK violation" } },
      },
    });
    const result = await deleteExerciseVideoAction("vid-1", "ex-1");
    expect(result.error).toBe("FK violation");
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});
