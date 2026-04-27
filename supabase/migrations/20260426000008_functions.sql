-- Migration: Business functions — exercise alternatives, plan/routine/session cloning

-- ============================================================
-- get_exercise_alternatives
-- Returns exercises in the same category as the given exercise,
-- excluding the exercise itself, ordered by name.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_exercise_alternatives(
  p_user_id   UUID,
  p_exercise_id UUID,
  p_limit     INT DEFAULT 10
)
RETURNS TABLE (
  id            UUID,
  name          TEXT,
  category      exercise_category,
  muscle_groups TEXT[],
  is_public     BOOLEAN,
  user_id       UUID
)
LANGUAGE sql
SECURITY INVOKER
STABLE AS $$
  SELECT
    e.id,
    e.name,
    e.category,
    e.muscle_groups,
    e.is_public,
    e.user_id
  FROM public.exercises e
  WHERE
    e.category = (SELECT category FROM public.exercises WHERE id = p_exercise_id)
    AND e.id <> p_exercise_id
    AND e.is_active = true
    AND (e.user_id = p_user_id OR e.user_id IS NULL)
  ORDER BY e.name
  LIMIT p_limit;
$$;

-- ============================================================
-- clone_plan
-- Deep-clones a plan and all its plan_routines into a new plan
-- owned by the calling user. Returns the new plan's UUID.
-- ============================================================
CREATE OR REPLACE FUNCTION public.clone_plan(
  p_plan_id  UUID,
  p_new_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER AS $$
DECLARE
  v_new_plan_id UUID;
BEGIN
  -- Clone the plan header
  INSERT INTO public.plans (user_id, name, description, duration_weeks, is_active, is_public)
  SELECT auth.uid(), p_new_name, description, duration_weeks, is_active, false
  FROM public.plans
  WHERE id = p_plan_id
  RETURNING id INTO v_new_plan_id;

  -- Clone plan_routines preserving order
  INSERT INTO public.plan_routines (plan_id, routine_id, order_index)
  SELECT v_new_plan_id, routine_id, order_index
  FROM public.plan_routines
  WHERE plan_id = p_plan_id
  ORDER BY order_index;

  RETURN v_new_plan_id;
END $$;

-- ============================================================
-- clone_routine
-- Deep-clones a routine and all its routine_sessions into a new
-- routine owned by the calling user. Returns the new routine UUID.
-- ============================================================
CREATE OR REPLACE FUNCTION public.clone_routine(
  p_routine_id UUID,
  p_new_name   TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER AS $$
DECLARE
  v_new_routine_id UUID;
BEGIN
  -- Clone the routine header
  INSERT INTO public.routines (user_id, name, description, is_active, is_public)
  SELECT auth.uid(), p_new_name, description, is_active, false
  FROM public.routines
  WHERE id = p_routine_id
  RETURNING id INTO v_new_routine_id;

  -- Clone routine_sessions preserving order
  INSERT INTO public.routine_sessions (routine_id, session_id, order_index)
  SELECT v_new_routine_id, session_id, order_index
  FROM public.routine_sessions
  WHERE routine_id = p_routine_id
  ORDER BY order_index;

  RETURN v_new_routine_id;
END $$;

-- ============================================================
-- clone_session
-- Deep-clones a session and all its session_exercises into a new
-- session owned by the calling user. Returns the new session UUID.
-- ============================================================
CREATE OR REPLACE FUNCTION public.clone_session(
  p_session_id UUID,
  p_new_name   TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER AS $$
DECLARE
  v_new_session_id UUID;
BEGIN
  -- Clone the session header
  INSERT INTO public.sessions (user_id, name, description, rest_between_exercises_seconds, is_public)
  SELECT auth.uid(), p_new_name, description, rest_between_exercises_seconds, false
  FROM public.sessions
  WHERE id = p_session_id
  RETURNING id INTO v_new_session_id;

  -- Clone session_exercises preserving order and configuration
  INSERT INTO public.session_exercises (
    session_id, exercise_id, order_index,
    target_sets, target_reps, target_weight,
    rest_between_sets_seconds, notes
  )
  SELECT
    v_new_session_id, exercise_id, order_index,
    target_sets, target_reps, target_weight,
    rest_between_sets_seconds, notes
  FROM public.session_exercises
  WHERE session_id = p_session_id
  ORDER BY order_index;

  RETURN v_new_session_id;
END $$;
