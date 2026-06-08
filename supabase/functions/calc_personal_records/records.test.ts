import { assertEquals } from "jsr:@std/assert@1";
import { computeBestRecords, type SetRow, toKg } from "./records.ts";

function set(partial: Partial<SetRow> & { id: string }): SetRow {
  return {
    reps: null,
    weight: null,
    weight_unit: "kg",
    completed_at: "2026-06-01T10:00:00Z",
    ...partial,
  };
}

Deno.test("toKg deja kg igual y convierte lb", () => {
  assertEquals(toKg(100, "kg"), 100);
  assertEquals(Math.round(toKg(100, "lb")), 45);
  assertEquals(toKg(null, "kg"), 0);
});

Deno.test("computeBestRecords detecta mejor peso, reps y volumen", () => {
  const sets = [
    set({ id: "a", reps: 5, weight: 100 }), // vol 500
    set({ id: "b", reps: 10, weight: 80 }), // vol 800 (mejor volumen)
    set({ id: "c", reps: 12, weight: 60 }), // mejores reps
  ];
  const records = computeBestRecords(sets);
  const byType = new Map(records.map((r) => [r.record_type, r]));

  assertEquals(byType.get("max_weight")?.value, 100);
  assertEquals(byType.get("max_weight")?.exercise_set_id, "a");
  assertEquals(byType.get("max_reps")?.value, 12);
  assertEquals(byType.get("max_reps")?.exercise_set_id, "c");
  assertEquals(byType.get("max_volume")?.value, 800);
  assertEquals(byType.get("max_volume")?.exercise_set_id, "b");
});

Deno.test("anti-fantasma: si todas las series bajan, el récord baja", () => {
  // El usuario corrige un peso mal cargado de 200 a 90 en todos sus sets.
  const sets = [set({ id: "a", reps: 5, weight: 90 }), set({ id: "b", reps: 5, weight: 85 })];
  const records = computeBestRecords(sets);
  const maxWeight = records.find((r) => r.record_type === "max_weight");
  assertEquals(maxWeight?.value, 90); // ya no hay rastro del 200 fantasma
});

Deno.test("normaliza a kg al comparar unidades mezcladas", () => {
  const sets = [
    set({ id: "kg", reps: 1, weight: 100, weight_unit: "kg" }), // 100 kg
    set({ id: "lb", reps: 1, weight: 225, weight_unit: "lb" }), // ~102 kg (mejor)
  ];
  const records = computeBestRecords(sets);
  const maxWeight = records.find((r) => r.record_type === "max_weight");
  assertEquals(maxWeight?.exercise_set_id, "lb");
});

Deno.test("omite tipos sin datos (sets sin peso → sin max_weight ni max_volume)", () => {
  const sets = [set({ id: "a", reps: 10, weight: null }), set({ id: "b", reps: 8, weight: null })];
  const records = computeBestRecords(sets);
  const types = records.map((r) => r.record_type);
  assertEquals(types.includes("max_weight"), false);
  assertEquals(types.includes("max_volume"), false);
  assertEquals(types.includes("max_reps"), true);
});
