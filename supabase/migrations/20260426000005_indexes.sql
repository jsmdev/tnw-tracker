-- Migration: Performance indexes and realtime publication

-- Exercises
CREATE INDEX IF NOT EXISTS idx_exercises_user
  ON public.exercises(user_id) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_exercises_name_trgm
  ON public.exercises USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_exercises_category
  ON public.exercises(category) WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_exercises_muscle_groups_gin
  ON public.exercises USING gin (muscle_groups);

-- Template joins
CREATE INDEX IF NOT EXISTS idx_session_exercises_session
  ON public.session_exercises(session_id, order_index);

CREATE INDEX IF NOT EXISTS idx_session_exercises_exercise
  ON public.session_exercises(exercise_id);

CREATE INDEX IF NOT EXISTS idx_routine_sessions_routine
  ON public.routine_sessions(routine_id, order_index);

CREATE INDEX IF NOT EXISTS idx_plan_routines_plan
  ON public.plan_routines(plan_id, order_index);

-- Workouts history
CREATE INDEX IF NOT EXISTS idx_workouts_user_started
  ON public.workouts(user_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_workouts_session
  ON public.workouts(session_id) WHERE session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_workout_exercises_workout
  ON public.workout_exercises(workout_id, order_index);

CREATE INDEX IF NOT EXISTS idx_exercise_sets_we
  ON public.exercise_sets(workout_exercise_id, set_number);

-- Personal records
CREATE INDEX IF NOT EXISTS idx_pr_user_exercise_type
  ON public.personal_records(user_id, exercise_id, record_type, achieved_at DESC);

-- Rest timers
CREATE INDEX IF NOT EXISTS idx_rest_timers_ends_at
  ON public.rest_timers(ends_at) WHERE is_active = true;

-- Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.rest_timers;
