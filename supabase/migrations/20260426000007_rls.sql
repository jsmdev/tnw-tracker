-- Migration: Row Level Security — all business tables

-- ============================================================
-- users
-- ============================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users: select own" ON public.users
  FOR SELECT USING (id = auth.uid());

CREATE POLICY "users: insert own" ON public.users
  FOR INSERT WITH CHECK (id = auth.uid());

CREATE POLICY "users: update own" ON public.users
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

CREATE POLICY "users: delete own" ON public.users
  FOR DELETE USING (id = auth.uid());

-- ============================================================
-- exercises
-- Global exercises (user_id IS NULL) are visible to all authenticated users.
-- ============================================================
ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercises: select own or global" ON public.exercises
  FOR SELECT USING (user_id = auth.uid() OR user_id IS NULL);

CREATE POLICY "exercises: insert own" ON public.exercises
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "exercises: update own" ON public.exercises
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "exercises: delete own" ON public.exercises
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================
-- exercise_videos
-- Visible when the parent exercise is accessible.
-- ============================================================
ALTER TABLE public.exercise_videos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercise_videos: select via exercise" ON public.exercise_videos
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.exercises e
      WHERE e.id = exercise_id
        AND (e.user_id = auth.uid() OR e.user_id IS NULL)
    )
  );

CREATE POLICY "exercise_videos: insert via own exercise" ON public.exercise_videos
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.exercises e
      WHERE e.id = exercise_id AND e.user_id = auth.uid()
    )
  );

CREATE POLICY "exercise_videos: update via own exercise" ON public.exercise_videos
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.exercises e
      WHERE e.id = exercise_id AND e.user_id = auth.uid()
    )
  );

CREATE POLICY "exercise_videos: delete via own exercise" ON public.exercise_videos
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.exercises e
      WHERE e.id = exercise_id AND e.user_id = auth.uid()
    )
  );

-- ============================================================
-- plans
-- ============================================================
ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "plans: select own or public" ON public.plans
  FOR SELECT USING (user_id = auth.uid() OR is_public = true);

CREATE POLICY "plans: insert own" ON public.plans
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "plans: update own" ON public.plans
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "plans: delete own" ON public.plans
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================
-- routines
-- ============================================================
ALTER TABLE public.routines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "routines: select own or public" ON public.routines
  FOR SELECT USING (user_id = auth.uid() OR is_public = true);

CREATE POLICY "routines: insert own" ON public.routines
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "routines: update own" ON public.routines
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "routines: delete own" ON public.routines
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================
-- plan_routines
-- ============================================================
ALTER TABLE public.plan_routines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "plan_routines: select via plan" ON public.plan_routines
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.plans p
      WHERE p.id = plan_id AND (p.user_id = auth.uid() OR p.is_public = true)
    )
  );

CREATE POLICY "plan_routines: insert via own plan" ON public.plan_routines
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.plans p
      WHERE p.id = plan_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "plan_routines: update via own plan" ON public.plan_routines
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.plans p
      WHERE p.id = plan_id AND p.user_id = auth.uid()
    )
  );

CREATE POLICY "plan_routines: delete via own plan" ON public.plan_routines
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.plans p
      WHERE p.id = plan_id AND p.user_id = auth.uid()
    )
  );

-- ============================================================
-- sessions
-- ============================================================
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sessions: select own or public" ON public.sessions
  FOR SELECT USING (user_id = auth.uid() OR is_public = true);

CREATE POLICY "sessions: insert own" ON public.sessions
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "sessions: update own" ON public.sessions
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "sessions: delete own" ON public.sessions
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================
-- routine_sessions
-- ============================================================
ALTER TABLE public.routine_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "routine_sessions: select via routine" ON public.routine_sessions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.routines r
      WHERE r.id = routine_id AND (r.user_id = auth.uid() OR r.is_public = true)
    )
  );

CREATE POLICY "routine_sessions: insert via own routine" ON public.routine_sessions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.routines r
      WHERE r.id = routine_id AND r.user_id = auth.uid()
    )
  );

CREATE POLICY "routine_sessions: update via own routine" ON public.routine_sessions
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.routines r
      WHERE r.id = routine_id AND r.user_id = auth.uid()
    )
  );

CREATE POLICY "routine_sessions: delete via own routine" ON public.routine_sessions
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.routines r
      WHERE r.id = routine_id AND r.user_id = auth.uid()
    )
  );

-- ============================================================
-- session_exercises
-- ============================================================
ALTER TABLE public.session_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "session_exercises: select via session" ON public.session_exercises
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id AND (s.user_id = auth.uid() OR s.is_public = true)
    )
  );

CREATE POLICY "session_exercises: insert via own session" ON public.session_exercises
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id AND s.user_id = auth.uid()
    )
  );

CREATE POLICY "session_exercises: update via own session" ON public.session_exercises
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id AND s.user_id = auth.uid()
    )
  );

CREATE POLICY "session_exercises: delete via own session" ON public.session_exercises
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.sessions s
      WHERE s.id = session_id AND s.user_id = auth.uid()
    )
  );

-- ============================================================
-- workouts
-- ============================================================
ALTER TABLE public.workouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workouts: select own" ON public.workouts
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "workouts: insert own" ON public.workouts
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "workouts: update own" ON public.workouts
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "workouts: delete own" ON public.workouts
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================
-- workout_exercises
-- ============================================================
ALTER TABLE public.workout_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workout_exercises: select via workout" ON public.workout_exercises
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "workout_exercises: insert via own workout" ON public.workout_exercises
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "workout_exercises: update via own workout" ON public.workout_exercises
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "workout_exercises: delete via own workout" ON public.workout_exercises
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

-- ============================================================
-- exercise_sets
-- ============================================================
ALTER TABLE public.exercise_sets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercise_sets: select via workout" ON public.exercise_sets
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.workout_exercises we
      JOIN public.workouts w ON w.id = we.workout_id
      WHERE we.id = workout_exercise_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "exercise_sets: insert via own workout" ON public.exercise_sets
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.workout_exercises we
      JOIN public.workouts w ON w.id = we.workout_id
      WHERE we.id = workout_exercise_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "exercise_sets: update via own workout" ON public.exercise_sets
  FOR UPDATE USING (
    EXISTS (
      SELECT 1
      FROM public.workout_exercises we
      JOIN public.workouts w ON w.id = we.workout_id
      WHERE we.id = workout_exercise_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "exercise_sets: delete via own workout" ON public.exercise_sets
  FOR DELETE USING (
    EXISTS (
      SELECT 1
      FROM public.workout_exercises we
      JOIN public.workouts w ON w.id = we.workout_id
      WHERE we.id = workout_exercise_id AND w.user_id = auth.uid()
    )
  );

-- ============================================================
-- rest_timers
-- ============================================================
ALTER TABLE public.rest_timers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rest_timers: select via workout" ON public.rest_timers
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "rest_timers: insert via own workout" ON public.rest_timers
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "rest_timers: update via own workout" ON public.rest_timers
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

CREATE POLICY "rest_timers: delete via own workout" ON public.rest_timers
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.workouts w
      WHERE w.id = workout_id AND w.user_id = auth.uid()
    )
  );

-- ============================================================
-- personal_records
-- ============================================================
ALTER TABLE public.personal_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "personal_records: select own" ON public.personal_records
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "personal_records: insert own" ON public.personal_records
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "personal_records: update own" ON public.personal_records
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "personal_records: delete own" ON public.personal_records
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================
-- motivational_quotes — public read, admin-only write (no user column)
-- ============================================================
ALTER TABLE public.motivational_quotes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "motivational_quotes: select all authenticated" ON public.motivational_quotes
  FOR SELECT USING (auth.role() = 'authenticated');
