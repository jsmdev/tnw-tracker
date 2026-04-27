-- pgTAP constraint tests
BEGIN;

SELECT plan(7);

-- ---------------------------------------------------------------
-- Helpers: seed data
-- Insert into auth.users first — the trigger on_auth_user_created
-- will create the corresponding public.users rows automatically.
-- ---------------------------------------------------------------
INSERT INTO auth.users (
    id, instance_id, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, role
)
VALUES
  (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'user1@test.com', '',
    now(), now(), now(),
    '{}', '{}',
    false, 'authenticated'
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'user2@test.com', '',
    now(), now(), now(),
    '{}', '{}',
    false, 'authenticated'
  );

-- Insert an exercise
INSERT INTO public.exercises (id, user_id, name, category)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Bench Press', 'Push');

-- Insert a session
INSERT INTO public.sessions (id, user_id, name)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Session A');

-- Insert a plan
INSERT INTO public.plans (id, user_id, name)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Plan A');

-- Insert a workout (active)
INSERT INTO public.workouts (id, user_id, name, status)
VALUES ('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Workout 1', 'active');

-- Insert a workout_exercise
INSERT INTO public.workout_exercises (id, workout_id, exercise_id, order_index)
VALUES ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', 1);

-- ---------------------------------------------------------------
-- Test 1: Only one active/paused workout per user (unique partial index)
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$
    INSERT INTO public.workouts (user_id, name, status)
    VALUES ('00000000-0000-0000-0000-000000000001', 'Workout 2', 'active')
  $$,
  '23505',
  NULL,
  'Should reject a second active workout for the same user'
);

-- ---------------------------------------------------------------
-- Test 2: A paused workout also conflicts with an active one
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$
    INSERT INTO public.workouts (user_id, name, status)
    VALUES ('00000000-0000-0000-0000-000000000001', 'Workout 3', 'paused')
  $$,
  '23505',
  NULL,
  'Should reject a paused workout when an active one exists for the same user'
);

-- ---------------------------------------------------------------
-- Test 3: Only one active rest timer per workout
-- ---------------------------------------------------------------
INSERT INTO public.rest_timers (id, workout_id, timer_type, duration_seconds, started_at, ends_at, is_active)
VALUES (
  'ffffffff-0000-0000-0000-000000000001',
  'cccccccc-0000-0000-0000-000000000001',
  'between_sets', 90,
  now(), now() + interval '90 seconds',
  true
);

SELECT throws_ok(
  $$
    INSERT INTO public.rest_timers (workout_id, timer_type, duration_seconds, started_at, ends_at, is_active)
    VALUES (
      'cccccccc-0000-0000-0000-000000000001',
      'between_exercises', 60,
      now(), now() + interval '60 seconds',
      true
    )
  $$,
  '23505',
  NULL,
  'Should reject a second active timer for the same workout'
);

-- ---------------------------------------------------------------
-- Test 4: RPE CHECK — value 11 must be rejected
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$
    INSERT INTO public.exercise_sets (workout_exercise_id, set_number, rpe)
    VALUES ('dddddddd-0000-0000-0000-000000000001', 1, 11)
  $$,
  '23514',
  NULL,
  'RPE value 11 should violate CHECK constraint'
);

-- ---------------------------------------------------------------
-- Test 5: RPE CHECK — value 0 must be rejected
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$
    INSERT INTO public.exercise_sets (workout_exercise_id, set_number, rpe)
    VALUES ('dddddddd-0000-0000-0000-000000000001', 1, 0)
  $$,
  '23514',
  NULL,
  'RPE value 0 should violate CHECK constraint'
);

-- ---------------------------------------------------------------
-- Test 6: UNIQUE (workout_exercise_id, set_number)
-- ---------------------------------------------------------------
INSERT INTO public.exercise_sets (workout_exercise_id, set_number, reps, weight)
VALUES ('dddddddd-0000-0000-0000-000000000001', 1, 10, 60);

SELECT throws_ok(
  $$
    INSERT INTO public.exercise_sets (workout_exercise_id, set_number, reps, weight)
    VALUES ('dddddddd-0000-0000-0000-000000000001', 1, 8, 65)
  $$,
  '23505',
  NULL,
  'Duplicate (workout_exercise_id, set_number) should be rejected'
);

-- ---------------------------------------------------------------
-- Test 7: UNIQUE (plan_id, order_index) in plan_routines
-- ---------------------------------------------------------------
INSERT INTO public.routines (id, user_id, name)
VALUES
  ('11111111-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Routine A'),
  ('11111111-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Routine B');

INSERT INTO public.plan_routines (plan_id, routine_id, order_index)
VALUES ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 1);

SELECT throws_ok(
  $$
    INSERT INTO public.plan_routines (plan_id, routine_id, order_index)
    VALUES ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000002', 1)
  $$,
  '23505',
  NULL,
  'Duplicate (plan_id, order_index) in plan_routines should be rejected'
);

SELECT * FROM finish();

ROLLBACK;
