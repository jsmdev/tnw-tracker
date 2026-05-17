import { describe, it, expect, vi, beforeEach } from "vitest";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import {
  createPlanAction,
  updatePlanAction,
  deletePlanAction,
  reorderPlanRoutinesAction,
  addRoutineToPlanAction,
  removeRoutineFromPlanAction,
} from "@/app/actions/plan";

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));

const mockUser = { id: "user-123", email: "test@test.com" };

type Result = { data: unknown; error: unknown };

/**
 * Plan actions cover all the shapes from exercise.test.ts plus two new ones:
 *
 *   - `select(...).eq(...).order(...).limit(...).maybeSingle()` — used by
 *     `addRoutineToPlan` to find the current max order_index.
 *   - `supabase.rpc(name, params)` — used by `reorderPlanRoutinesAction`.
 *
 * `maybeSingle` is invoked twice in `addRoutineToPlan` happy paths: first by
 * `requireOwnership`, then by the order_index lookup. We support that by
 * passing `maybeSingleSequence` (an array consumed in order). The single-shot
 * `ownership` shortcut is preserved for the tests that only need one match.
 */
interface ClientOpts {
  user?: typeof mockUser | null;
  results?: {
    insertSelectSingle?: Result;
    updateChain?: Result;
    ownership?: Result;
    /** Sequence of values returned by successive maybeSingle() calls. Wins over `ownership` if both set. */
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

const VALID_PLAN = { name: "PPL 8-week" };

// =====================================================================
// createPlanAction
// =====================================================================

describe("createPlanAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: inserts and redirects to the new plan", async () => {
    const { client, chain } = makeClient({
      results: { insertSelectSingle: { data: { id: "plan-new" }, error: null } },
    });

    await expect(createPlanAction({}, formDataOf(VALID_PLAN))).rejects.toThrow("REDIRECT");

    expect(client.from).toHaveBeenCalledWith("plans");
    expect(chain.insert).toHaveBeenCalledWith({
      user_id: mockUser.id,
      name: "PPL 8-week",
      description: null,
      duration_weeks: null,
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/plans");
    expect(redirect).toHaveBeenCalledWith("/dashboard/plans/plan-new");
  });

  it("passes description and duration_weeks when present", async () => {
    const { chain } = makeClient({
      results: { insertSelectSingle: { data: { id: "plan-new" }, error: null } },
    });

    await expect(
      createPlanAction({}, formDataOf({ ...VALID_PLAN, description: "Test", duration_weeks: "8" }))
    ).rejects.toThrow("REDIRECT");

    expect(chain.insert).toHaveBeenCalledWith(
      expect.objectContaining({ description: "Test", duration_weeks: 8 })
    );
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(createPlanAction({}, formDataOf(VALID_PLAN))).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });

  it("returns field errors when name is empty", async () => {
    const { chain } = makeClient();
    const result = await createPlanAction({}, formDataOf({ name: "" }));
    expect(result.error?.name).toBeDefined();
    expect(chain.insert).not.toHaveBeenCalled();
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("returns the DB error message when insert fails", async () => {
    makeClient({
      results: { insertSelectSingle: { data: null, error: { message: "unique violation" } } },
    });
    const result = await createPlanAction({}, formDataOf(VALID_PLAN));
    expect(result.message).toBe("unique violation");
    expect(redirect).not.toHaveBeenCalled();
  });
});

// =====================================================================
// updatePlanAction
// =====================================================================

describe("updatePlanAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: updates scoped to (id, user_id) and revalidates both paths", async () => {
    const { chain } = makeClient();
    const result = await updatePlanAction("plan-1", {}, formDataOf(VALID_PLAN));

    expect(result).toEqual({ message: "Plan actualizado correctamente" });
    expect(chain.update).toHaveBeenCalledWith({
      name: "PPL 8-week",
      description: null,
      duration_weeks: null,
    });
    expect(chain.eq).toHaveBeenNthCalledWith(1, "id", "plan-1");
    expect(chain.eq).toHaveBeenNthCalledWith(2, "user_id", mockUser.id);
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/plans");
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/plans/plan-1");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(updatePlanAction("plan-1", {}, formDataOf(VALID_PLAN))).rejects.toThrow(
      "REDIRECT"
    );
  });

  it("returns field errors for invalid input", async () => {
    const { chain } = makeClient();
    const result = await updatePlanAction("plan-1", {}, formDataOf({ name: "" }));
    expect(result.error?.name).toBeDefined();
    expect(chain.update).not.toHaveBeenCalled();
  });

  it("returns the DB error message when update fails", async () => {
    makeClient({ results: { updateChain: { data: null, error: { message: "denied" } } } });
    const result = await updatePlanAction("plan-1", {}, formDataOf(VALID_PLAN));
    expect(result.message).toBe("denied");
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});

// =====================================================================
// deletePlanAction
// =====================================================================

describe("deletePlanAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("soft-deletes scoped to (id, user_id) and redirects to the list", async () => {
    const { chain } = makeClient();
    await expect(deletePlanAction("plan-1")).rejects.toThrow("REDIRECT");

    expect(chain.update).toHaveBeenCalledWith({ is_active: false });
    expect(chain.eq).toHaveBeenNthCalledWith(1, "id", "plan-1");
    expect(chain.eq).toHaveBeenNthCalledWith(2, "user_id", mockUser.id);
    expect(redirect).toHaveBeenCalledWith("/dashboard/plans");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(deletePlanAction("plan-1")).rejects.toThrow("REDIRECT");
    expect(redirect).toHaveBeenCalledWith("/login");
  });
});

// =====================================================================
// reorderPlanRoutinesAction
// =====================================================================

describe("reorderPlanRoutinesAction", () => {
  beforeEach(() => vi.clearAllMocks());

  const PR_1 = "11111111-1111-4111-8111-111111111111";
  const PR_2 = "22222222-2222-4222-8222-222222222222";
  const ITEMS = [
    { id: PR_1, orderIndex: 0 },
    { id: PR_2, orderIndex: 1 },
  ];

  it("happy path: calls rpc('reorder_items') with snake_case payload and revalidates", async () => {
    const { client } = makeClient({
      results: { ownership: { data: { id: "plan-1" }, error: null } },
    });

    const result = await reorderPlanRoutinesAction("plan-1", ITEMS);

    expect(result).toEqual({});
    expect(client.rpc).toHaveBeenCalledWith("reorder_items", {
      p_table: "plan_routines",
      p_parent_col: "plan_id",
      p_parent_id: "plan-1",
      p_items: [
        { id: PR_1, order_index: 0 },
        { id: PR_2, order_index: 1 },
      ],
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/plans/plan-1");
  });

  it("returns 'Datos inválidos' when the items array is invalid", async () => {
    const { client } = makeClient();
    // @ts-expect-error — intentionally bad shape
    const result = await reorderPlanRoutinesAction("plan-1", [{ id: "x" }]);
    expect(result).toEqual({ error: "Datos inválidos" });
    expect(client.rpc).not.toHaveBeenCalled();
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(reorderPlanRoutinesAction("plan-1", ITEMS)).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the plan does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await reorderPlanRoutinesAction("plan-1", ITEMS);
    expect(result).toEqual({ error: "No autorizado" });
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("maps RPC error 'unauthorized' to 'No autorizado'", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "plan-1" }, error: null },
        rpc: { data: null, error: { message: "unauthorized" } },
      },
    });
    const result = await reorderPlanRoutinesAction("plan-1", ITEMS);
    expect(result).toEqual({ error: "No autorizado" });
  });

  it("maps RPC error 'invalid_table' to 'Datos inválidos'", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "plan-1" }, error: null },
        rpc: { data: null, error: { message: "invalid_table" } },
      },
    });
    const result = await reorderPlanRoutinesAction("plan-1", ITEMS);
    expect(result).toEqual({ error: "Datos inválidos" });
  });

  it("falls through to the raw RPC error message for unknown errors", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "plan-1" }, error: null },
        rpc: { data: null, error: { message: "deadlock detected" } },
      },
    });
    const result = await reorderPlanRoutinesAction("plan-1", ITEMS);
    expect(result).toEqual({ error: "deadlock detected" });
  });
});

// =====================================================================
// addRoutineToPlanAction
// =====================================================================

describe("addRoutineToPlanAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path with no existing items: inserts at order_index 0", async () => {
    const { client, chain } = makeClient({
      results: {
        // first maybeSingle = ownership (data not null), second = no last item (null)
        maybeSingleSequence: [
          { data: { id: "plan-1" }, error: null },
          { data: null, error: null },
        ],
      },
    });

    const result = await addRoutineToPlanAction("plan-1", "rt-1");
    expect(result).toEqual({});
    expect(client.from).toHaveBeenCalledWith("plan_routines");
    expect(chain.insert).toHaveBeenCalledWith({
      plan_id: "plan-1",
      routine_id: "rt-1",
      order_index: 0,
    });
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/plans/plan-1");
  });

  it("happy path with existing items: inserts at last.order_index + 1", async () => {
    const { chain } = makeClient({
      results: {
        maybeSingleSequence: [
          { data: { id: "plan-1" }, error: null },
          { data: { order_index: 4 }, error: null },
        ],
      },
    });

    await addRoutineToPlanAction("plan-1", "rt-1");
    expect(chain.insert).toHaveBeenCalledWith(expect.objectContaining({ order_index: 5 }));
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(addRoutineToPlanAction("plan-1", "rt-1")).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the plan does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await addRoutineToPlanAction("plan-1", "rt-1");
    expect(result).toEqual({ error: "No autorizado" });
  });

  it("returns the insert error when Supabase fails", async () => {
    makeClient({
      results: {
        maybeSingleSequence: [
          { data: { id: "plan-1" }, error: null },
          { data: null, error: null },
        ],
        insertOnly: { data: null, error: { message: "FK violation" } },
      },
    });
    const result = await addRoutineToPlanAction("plan-1", "rt-1");
    expect(result).toEqual({ error: "FK violation" });
    expect(revalidatePath).not.toHaveBeenCalled();
  });
});

// =====================================================================
// removeRoutineFromPlanAction
// =====================================================================

describe("removeRoutineFromPlanAction", () => {
  beforeEach(() => vi.clearAllMocks());

  it("happy path: deletes the junction row and returns {}", async () => {
    const { client, chain } = makeClient({
      results: { ownership: { data: { id: "plan-1" }, error: null } },
    });

    const result = await removeRoutineFromPlanAction("pr-1", "plan-1");

    expect(result).toEqual({});
    expect(client.from).toHaveBeenCalledWith("plan_routines");
    expect(chain.delete).toHaveBeenCalled();
    expect(chain.eq).toHaveBeenCalledWith("id", "pr-1");
    expect(revalidatePath).toHaveBeenCalledWith("/dashboard/plans/plan-1");
  });

  it("redirects to /login when not authenticated", async () => {
    makeClient({ user: null });
    await expect(removeRoutineFromPlanAction("pr-1", "plan-1")).rejects.toThrow("REDIRECT");
  });

  it("returns 'No autorizado' when the plan does not belong to the user", async () => {
    makeClient({ results: { ownership: { data: null, error: null } } });
    const result = await removeRoutineFromPlanAction("pr-1", "plan-1");
    expect(result).toEqual({ error: "No autorizado" });
  });

  it("returns the delete error when Supabase fails", async () => {
    makeClient({
      results: {
        ownership: { data: { id: "plan-1" }, error: null },
        deleteChain: { data: null, error: { message: "constraint" } },
      },
    });
    const result = await removeRoutineFromPlanAction("pr-1", "plan-1");
    expect(result).toEqual({ error: "constraint" });
  });
});
