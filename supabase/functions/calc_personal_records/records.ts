// Lógica pura de cálculo de récords personales — sin dependencias de red,
// para poder testearla de forma aislada (ver records.test.ts).

export interface SetRow {
  id: string;
  reps: number | null;
  weight: number | null;
  weight_unit: string;
  completed_at: string | null;
}

export type RecordType = "max_weight" | "max_reps" | "max_volume";

export interface BestRecord {
  record_type: RecordType;
  value: number; // siempre en kg
  exercise_set_id: string;
  achieved_at: string;
}

export const ALL_TYPES: RecordType[] = ["max_weight", "max_reps", "max_volume"];

export function toKg(weight: number | null, unit: string): number {
  if (weight == null) return 0;
  return unit === "lb" ? weight * 0.453592 : weight;
}

/**
 * Calcula la mejor marca por tipo a partir de TODAS las series completadas
 * (sin calentamiento) de un ejercicio. Devuelve sólo los tipos con datos:
 * si no hay ninguna serie con peso/reps válidos, ese tipo se omite — y el
 * llamador lo interpreta como "borrar el récord vigente" (anti-fantasma).
 */
export function computeBestRecords(sets: SetRow[]): BestRecord[] {
  let weight: BestRecord | null = null;
  let reps: BestRecord | null = null;
  let volume: BestRecord | null = null;

  for (const s of sets) {
    const achievedAt = s.completed_at ?? "";
    const weightKg = toKg(s.weight, s.weight_unit);
    const repCount = s.reps ?? 0;

    if (s.weight != null && weightKg > 0 && (weight === null || weightKg > weight.value)) {
      weight = {
        record_type: "max_weight",
        value: weightKg,
        exercise_set_id: s.id,
        achieved_at: achievedAt,
      };
    }
    if (s.reps != null && repCount > 0 && (reps === null || repCount > reps.value)) {
      reps = {
        record_type: "max_reps",
        value: repCount,
        exercise_set_id: s.id,
        achieved_at: achievedAt,
      };
    }
    const vol = repCount * weightKg;
    if (vol > 0 && (volume === null || vol > volume.value)) {
      volume = {
        record_type: "max_volume",
        value: vol,
        exercise_set_id: s.id,
        achieved_at: achievedAt,
      };
    }
  }

  return [weight, reps, volume].filter((r): r is BestRecord => r !== null);
}
