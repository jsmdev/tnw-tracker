-- pgTAP: sync of muscle groups, routine items and exercise settings (issue #135, T6).
-- exercise_muscle_groups keeps a position. Deleting a muscle group, routine
-- item or exercise setting on its own records a tombstone of its owner (row_id
-- is the exercise id for a setting); one deleted with its parent records none;
-- inserting it again clears it. Owners read only their own.
BEGIN;

SELECT plan(28);

-- ---------------------------------------------------------------
-- Fixtures (as postgres, RLS bypassed)
-- ---------------------------------------------------------------
INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role
) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'one@example.test', '', now(), now(), now(), '{}', '{}', false, 'authenticated'),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'two@example.test', '', now(), now(), now(), '{}', '{}', false, 'authenticated');

INSERT INTO public.exercises (id, user_id, name, type) VALUES
  ('c0000000-0000-0000-0000-000000000001', NULL, 'Catalog Squat', 'strength'),
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Own Lunge', 'strength'),
  ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Own Row', 'strength'),
  ('a2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Other Lunge', 'strength');

INSERT INTO public.exercise_muscle_groups (id, exercise_id, muscle, role, position) VALUES
  ('91000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'quadriceps', 'primary', 1),
  ('91000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'glutes', 'secondary', 2),
  ('91000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000002', 'back', 'primary', 1),
  ('90000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'quadriceps', 'primary', 1);

INSERT INTO public.routines (id, user_id, name) VALUES
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Routine One'),
  ('b1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Routine Gone');

INSERT INTO public.routine_items (id, user_id, routine_id, position, exercise_id) VALUES
  ('b1100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001', 1, 'c0000000-0000-0000-0000-000000000001'),
  ('b1100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001', 2, 'c0000000-0000-0000-0000-000000000001'),
  ('b1200000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000002', 1, 'c0000000-0000-0000-0000-000000000001');

INSERT INTO public.exercise_settings (user_id, exercise_id, rest_seconds) VALUES
  ('00000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 60),
  ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002', 75),
  ('00000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 45);

CREATE FUNCTION pg_temp.tombstones_of(owner uuid) RETURNS text[]
LANGUAGE sql AS $$
  SELECT coalesce(array_agg(table_name || ':' || row_id ORDER BY table_name, row_id), '{}')
  FROM public.tombstones WHERE user_id = owner
$$;

-- ---------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------
SELECT has_column('public', 'exercise_muscle_groups', 'position', 'exercise_muscle_groups has a position');
SELECT col_type_is('public', 'exercise_muscle_groups', 'position', 'integer', 'exercise_muscle_groups.position is an integer');
SELECT col_not_null('public', 'exercise_muscle_groups', 'position', 'exercise_muscle_groups.position is never null');
SELECT col_default_is('public', 'exercise_muscle_groups', 'position', '1', 'exercise_muscle_groups.position defaults to 1');
SELECT throws_ok(
  $$ UPDATE public.exercise_muscle_groups SET position = 0 WHERE id = '91000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'a muscle group position starts at 1'
);
SELECT has_trigger('public', 'exercise_muscle_groups', 'record_tombstones', 'muscle group deletes record tombstones');
SELECT has_trigger('public', 'routine_items', 'record_tombstones', 'routine item deletes record tombstones');
SELECT has_trigger('public', 'exercise_settings', 'record_tombstones', 'exercise setting deletes record tombstones');
SELECT has_trigger('public', 'exercise_settings', 'clear_tombstones', 'exercise setting inserts clear tombstones');

-- ---------------------------------------------------------------
-- The owner deletes child rows through the API
-- ---------------------------------------------------------------
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

UPDATE public.exercise_muscle_groups SET position = 3 WHERE id = '91000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT position FROM public.exercise_muscle_groups WHERE id = '91000000-0000-0000-0000-000000000002'), 3,
  'the owner moves a muscle of their exercise'
);
SELECT is((SELECT count(*)::int FROM public.tombstones), 0, 'an update records no tombstone');

DELETE FROM public.exercise_muscle_groups WHERE id = '91000000-0000-0000-0000-000000000002';
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'),
  ARRAY['exercise_muscle_groups:91000000-0000-0000-0000-000000000002'],
  'deleting a muscle group records a tombstone of its exercise''s owner'
);

DELETE FROM public.routine_items WHERE id = 'b1100000-0000-0000-0000-000000000002';
SELECT ok(
  'routine_items:b1100000-0000-0000-0000-000000000002' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'deleting a routine item records its tombstone'
);

DELETE FROM public.exercise_settings WHERE exercise_id = 'c0000000-0000-0000-0000-000000000001';
SELECT ok(
  'exercise_settings:c0000000-0000-0000-0000-000000000001' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'deleting an exercise setting records a tombstone keyed by its exercise'
);
SELECT is((SELECT count(*)::int FROM public.tombstones), 3, 'one tombstone per deleted row');

-- Deleted with their parent: only the parent's tombstone.
DELETE FROM public.routines WHERE id = 'b1000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE row_id = 'b1200000-0000-0000-0000-000000000001'), 0,
  'a routine item deleted with its routine leaves no tombstone of its own'
);
DELETE FROM public.exercises WHERE id = 'a1000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM public.tombstones
    WHERE table_name IN ('exercise_muscle_groups', 'exercise_settings')
      AND row_id IN ('91000000-0000-0000-0000-000000000003', 'a1000000-0000-0000-0000-000000000002')), 0,
  'the muscles and setting deleted with their exercise leave no tombstone of their own'
);
SELECT is((SELECT count(*)::int FROM public.tombstones), 5, 'only the parents were added');

-- Written again under the same key: the tombstone goes.
INSERT INTO public.exercise_muscle_groups (id, exercise_id, muscle, role, position) VALUES
  ('91000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001', 'glutes', 'secondary', 2)
ON CONFLICT (id) DO UPDATE SET position = EXCLUDED.position;
INSERT INTO public.routine_items (id, user_id, routine_id, position, exercise_id) VALUES
  ('b1100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001', 2, 'c0000000-0000-0000-0000-000000000001')
ON CONFLICT (id) DO UPDATE SET position = EXCLUDED.position;
INSERT INTO public.exercise_settings (user_id, exercise_id, rest_seconds) VALUES
  ('00000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 60)
ON CONFLICT (user_id, exercise_id) DO UPDATE SET rest_seconds = EXCLUDED.rest_seconds;
SELECT is(
  (SELECT count(*)::int FROM public.tombstones
    WHERE table_name IN ('exercise_muscle_groups', 'routine_items', 'exercise_settings')), 0,
  'a muscle group, routine item or setting written again clears its tombstone'
);
SELECT is((SELECT count(*)::int FROM public.tombstones), 2, 'the parents'' tombstones stay');

-- ---------------------------------------------------------------
-- Another user
-- ---------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
DELETE FROM public.exercise_settings WHERE exercise_id = 'c0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM public.tombstones), 1,
  'another user reads only their own tombstone'
);
RESET role;
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000002'),
  ARRAY['exercise_settings:c0000000-0000-0000-0000-000000000001'],
  'deleting their own setting of a shared catalogue exercise records it for them'
);
SELECT is(
  (SELECT rest_seconds FROM public.exercise_settings
    WHERE user_id = '00000000-0000-0000-0000-000000000001' AND exercise_id = 'c0000000-0000-0000-0000-000000000001'), 60,
  'the first user''s setting of that exercise is untouched'
);
-- Inserting the setting again clears only that user's tombstone.
INSERT INTO public.exercise_settings (user_id, exercise_id) VALUES
  ('00000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001');
SELECT is(pg_temp.tombstones_of('00000000-0000-0000-0000-000000000002'), '{}', 'their tombstone is cleared');

-- ---------------------------------------------------------------
-- Writes outside the app
-- ---------------------------------------------------------------
SET LOCAL role = service_role;
DELETE FROM public.exercise_muscle_groups WHERE id = '90000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE row_id = '90000000-0000-0000-0000-000000000001'), 0,
  'a catalogue exercise''s muscle belongs to nobody: no tombstone'
);
DELETE FROM public.routine_items WHERE id = 'b1100000-0000-0000-0000-000000000001';
SELECT ok(
  'routine_items:b1100000-0000-0000-0000-000000000001' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'a service-role delete of a routine item records a tombstone of its owner'
);
RESET role;

-- ---------------------------------------------------------------
-- Account deletion
-- ---------------------------------------------------------------
SELECT lives_ok(
  $$ DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000001' $$,
  'deleting an account with muscle groups, routine items and settings succeeds'
);
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE user_id = '00000000-0000-0000-0000-000000000001'), 0,
  'no tombstone of the deleted account remains'
);

SELECT * FROM finish();
ROLLBACK;
