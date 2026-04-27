-- Migration: Materialized view — mv_user_weekly_volume

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_user_weekly_volume AS
SELECT
  w.user_id,
  date_trunc('week', w.started_at)::DATE  AS week_start,
  COUNT(DISTINCT w.id)                    AS total_workouts,
  COUNT(es.id)                            AS total_sets,
  COALESCE(SUM(
    CASE es.weight_unit
      WHEN 'lb' THEN es.weight * 0.453592
      ELSE es.weight
    END * es.reps
  ), 0)                                   AS total_volume_kg,
  SUM(w.duration_seconds)                 AS total_duration_seconds
FROM public.workouts w
JOIN public.workout_exercises we ON we.workout_id = w.id
JOIN public.exercise_sets es    ON es.workout_exercise_id = we.id
WHERE
  w.status = 'completed'
  AND es.is_warmup = false
  AND es.completed_at IS NOT NULL
GROUP BY
  w.user_id,
  date_trunc('week', w.started_at)::DATE;

-- Unique index required for REFRESH MATERIALIZED VIEW CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_weekly_volume_user_week
  ON public.mv_user_weekly_volume (user_id, week_start);
