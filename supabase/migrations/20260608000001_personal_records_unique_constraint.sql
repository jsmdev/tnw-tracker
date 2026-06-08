-- Migration: personal_records pasa de historial (N filas por combo) a estado
-- actual (1 fila por user/exercise/record_type con la mejor marca real).
--
-- Motivo: calc_personal_records era append-only y sólo miraba el workout
-- recién cerrado, dejando "récords fantasma" cuando una serie se editaba a la
-- baja. Con una fila única por combo, la función puede recomputar (UPSERT) la
-- mejor marca real desde todos los sets completados del usuario.

-- 1. Dedup: conservar, por cada (user_id, exercise_id, record_type), la fila con
--    mayor valor normalizado a kg (desempata por achieved_at más reciente).
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, exercise_id, record_type
      ORDER BY
        (CASE WHEN weight_unit = 'lb' THEN value * 0.453592 ELSE value END) DESC,
        achieved_at DESC
    ) AS rn
  FROM public.personal_records
)
DELETE FROM public.personal_records pr
USING ranked r
WHERE pr.id = r.id
  AND r.rn > 1;

-- 2. Unicidad: una sola marca vigente por combo. Habilita el UPSERT
--    (ON CONFLICT) de la Edge Function.
ALTER TABLE public.personal_records
  ADD CONSTRAINT personal_records_user_exercise_type_unique
  UNIQUE (user_id, exercise_id, record_type);
