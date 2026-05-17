import { describe, it, expect, vi, beforeEach } from "vitest";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { updateSettingsAction } from "@/app/actions/settings";

// revalidatePath no se mockea globalmente — lo hacemos local porque sólo
// algunos tests necesitan verificar que se llamó (happy path) o que NO se
// llamó (validation / DB error paths).
vi.mock("next/cache", () => ({
  revalidatePath: vi.fn(),
}));

const mockUser = { id: "user-123", email: "test@test.com" };

interface UpdateResult {
  data: unknown;
  error: unknown;
}

/**
 * Builds a Supabase client mock pre-loaded with:
 *   - `auth.getUser()` returning the given user (or null to simulate logged out)
 *   - `from(table).update(values).eq(col, val)` resolving to `updateResult`
 *
 * The chain is recorded on `client.from` / `chain.update` / `chain.eq` so tests
 * can assert exact arguments.
 */
function makeClient({
  user = mockUser as typeof mockUser | null,
  updateResult = { data: null, error: null } as UpdateResult,
} = {}) {
  const chain = {
    update: vi.fn().mockReturnThis(),
    eq: vi.fn().mockResolvedValue(updateResult),
  };
  const client = {
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user }, error: null }),
    },
    from: vi.fn(() => chain),
  };
  vi.mocked(createClient).mockResolvedValue(client as never);
  return { client, chain };
}

function formDataOf(fields: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) fd.append(k, v);
  return fd;
}

describe("updateSettingsAction", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("happy path", () => {
    it("returns success and persists the values when input is valid (kg + auto)", async () => {
      const { client, chain } = makeClient();
      const result = await updateSettingsAction(
        {},
        formDataOf({ weight_unit: "kg", timer_trigger_mode: "auto" })
      );

      expect(result).toEqual({ success: true, message: "Ajustes guardados." });
      expect(client.from).toHaveBeenCalledWith("users");
      expect(chain.update).toHaveBeenCalledWith({
        weight_unit: "kg",
        timer_trigger_mode: "auto",
      });
      expect(chain.eq).toHaveBeenCalledWith("id", mockUser.id);
      expect(revalidatePath).toHaveBeenCalledWith("/dashboard/settings");
    });

    it("also works with the alternate combo (lb + manual)", async () => {
      const { chain } = makeClient();
      const result = await updateSettingsAction(
        {},
        formDataOf({ weight_unit: "lb", timer_trigger_mode: "manual" })
      );

      expect(result.success).toBe(true);
      expect(chain.update).toHaveBeenCalledWith({
        weight_unit: "lb",
        timer_trigger_mode: "manual",
      });
    });
  });

  describe("auth", () => {
    it("redirects to /login when no user is authenticated", async () => {
      makeClient({ user: null });

      await expect(
        updateSettingsAction({}, formDataOf({ weight_unit: "kg", timer_trigger_mode: "auto" }))
      ).rejects.toThrow("REDIRECT");
    });
  });

  describe("validation", () => {
    it("returns field errors when weight_unit is invalid", async () => {
      const { chain } = makeClient();
      const result = await updateSettingsAction(
        {},
        formDataOf({ weight_unit: "stones", timer_trigger_mode: "auto" })
      );

      expect(result.success).toBeUndefined();
      expect(result.error?.weight_unit).toBeDefined();
      expect(chain.update).not.toHaveBeenCalled();
      expect(revalidatePath).not.toHaveBeenCalled();
    });

    it("returns field errors when timer_trigger_mode is invalid", async () => {
      const { chain } = makeClient();
      const result = await updateSettingsAction(
        {},
        formDataOf({ weight_unit: "kg", timer_trigger_mode: "instant" })
      );

      expect(result.error?.timer_trigger_mode).toBeDefined();
      expect(chain.update).not.toHaveBeenCalled();
    });

    it("returns field errors for both fields when both are missing", async () => {
      const { chain } = makeClient();
      const result = await updateSettingsAction({}, new FormData());

      expect(result.error?.weight_unit).toBeDefined();
      expect(result.error?.timer_trigger_mode).toBeDefined();
      expect(chain.update).not.toHaveBeenCalled();
    });
  });

  describe("database errors", () => {
    it("returns the DB error message and does not revalidate when update fails", async () => {
      makeClient({
        updateResult: { data: null, error: { message: "row-level security policy violation" } },
      });

      const result = await updateSettingsAction(
        {},
        formDataOf({ weight_unit: "kg", timer_trigger_mode: "auto" })
      );

      expect(result.success).toBeUndefined();
      expect(result.message).toBe("row-level security policy violation");
      expect(revalidatePath).not.toHaveBeenCalled();
    });
  });
});
