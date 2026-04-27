-- pgTAP RLS tests
BEGIN;

SELECT plan(2);

-- ---------------------------------------------------------------
-- Helpers: seed two users and one workout each
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

INSERT INTO public.workouts (id, user_id, name, status)
VALUES
  ('cccccccc-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'User1 Workout', 'completed'),
  ('cccccccc-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', 'User2 Workout', 'completed');

-- ---------------------------------------------------------------
-- Test 1: Immutable completed_at — UPDATE must be rejected
-- ---------------------------------------------------------------
INSERT INTO public.exercises (id, user_id, name, category)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Squat', 'Legs');

INSERT INTO public.workout_exercises (id, workout_id, exercise_id, order_index)
VALUES ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', 1);

INSERT INTO public.exercise_sets (id, workout_exercise_id, set_number, reps, weight, completed_at)
VALUES ('55555555-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 1, 5, 100, now());

SELECT throws_ok(
  $$
    UPDATE public.exercise_sets
    SET completed_at = now() + interval '1 hour'
    WHERE id = '55555555-0000-0000-0000-000000000001'
  $$,
  'P0001',
  'completed_at is immutable once set',
  'Updating completed_at after it was set should raise an exception'
);

-- ---------------------------------------------------------------
-- Test 2: RLS — User 1 cannot see User 2''s workouts
-- ---------------------------------------------------------------
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001"}';

SELECT is(
  (
    SELECT COUNT(*)::INT
    FROM public.workouts
    WHERE user_id = '00000000-0000-0000-0000-000000000002'
  ),
  0,
  'User 1 should see 0 rows from User 2''s workouts due to RLS'
);

SELECT * FROM finish();

ROLLBACK;
