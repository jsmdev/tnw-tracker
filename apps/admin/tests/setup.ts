import "@testing-library/jest-dom";
import { vi } from "vitest";

// Mock global de next/navigation
// redirect() lanza un error para que sea testeable (no interrumpe el proceso de test)
vi.mock("next/navigation", () => ({
  redirect: vi.fn(() => {
    throw new Error("REDIRECT");
  }),
  useRouter: vi.fn(),
}));

// Mock global de @/lib/supabase/server
// createClient devuelve un cliente chainable que simula la API de Supabase.
// Tests individuales pueden sobrescribir comportamientos con vi.mocked(...).mockResolvedValueOnce
// Para tests que requieren cliente real, usar vi.unmock('@/lib/supabase/server') localmente.
vi.mock("@/lib/supabase/server", () => {
  const makeChain = (finalValue: { data: unknown; error: unknown }) => ({
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    neq: vi.fn().mockReturnThis(),
    gt: vi.fn().mockReturnThis(),
    lt: vi.fn().mockReturnThis(),
    gte: vi.fn().mockReturnThis(),
    lte: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    single: vi.fn().mockResolvedValue(finalValue),
    maybeSingle: vi.fn().mockResolvedValue(finalValue),
    insert: vi.fn().mockResolvedValue(finalValue),
    update: vi.fn().mockReturnThis(),
    delete: vi.fn().mockReturnThis(),
  });

  const defaultChain = makeChain({ data: null, error: null });

  const mockClient = {
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user: null }, error: null }),
    },
    from: vi.fn(() => defaultChain),
  };

  return {
    createClient: vi.fn().mockResolvedValue(mockClient),
  };
});
