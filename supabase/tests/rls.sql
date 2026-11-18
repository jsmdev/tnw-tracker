-- pgTAP: row level security per user (S2).
-- Owners read and write their rows; another user sees nothing, cannot write
-- into them, and cannot point their own rows at them. Catalog exercises
-- (user_id IS NULL) are readable by every signed-in user and writable by none.
BEGIN;

SELECT plan(90);

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
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Private One', 'strength'),
  ('a2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Private Two', 'strength');

INSERT INTO public.exercise_muscle_groups (exercise_id, muscle, role) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'quadriceps', 'primary'),
  ('a1000000-0000-0000-0000-000000000001', 'chest', 'primary');

INSERT INTO public.routines (id, user_id, name) VALUES
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Routine One');

INSERT INTO public.routines (id, user_id, name) VALUES
  ('b2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Routine Two');

INSERT INTO public.routine_items (id, user_id, routine_id, position, exercise_id) VALUES
  ('b1100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001', 1, 'a1000000-0000-0000-0000-000000000001');

INSERT INTO public.sessions (id, user_id, completed_at, time_zone) VALUES
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', now(), 'Europe/Madrid'),
  ('d2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', now(), 'UTC');

INSERT INTO public.entries (id, user_id, session_id, position, exercise_id, status) VALUES
  ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'd1000000-0000-0000-0000-000000000001', 1, 'a1000000-0000-0000-0000-000000000001', 'done');

INSERT INTO public.sets (id, user_id, entry_id, position, source, reps, weight, weight_unit) VALUES
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000001', 1, 'manual', 8, 60, 'kg');

INSERT INTO public.exercise_settings (user_id, exercise_id, rest_seconds) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 120),
  ('00000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000001', 60),
  ('00000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 75);

-- ===============================================================
-- Owner: user one
-- ===============================================================
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is((SELECT count(*)::int FROM public.users), 1, 'owner sees own profile only');
SELECT is(
  (SELECT count(*)::int FROM public.exercises
    WHERE id IN ('c0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
                 'a2000000-0000-0000-0000-000000000001')),
  2, 'owner sees own and catalog exercises, not another user''s'
);
SELECT is(
  (SELECT count(*)::int FROM public.exercise_muscle_groups
    WHERE exercise_id IN ('c0000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001')),
  2, 'owner sees muscle groups of own and catalog exercises'
);
SELECT is((SELECT count(*)::int FROM public.routines), 1, 'owner sees own routine');
SELECT is((SELECT count(*)::int FROM public.routine_items), 1, 'owner sees own routine item');
SELECT is((SELECT count(*)::int FROM public.sessions), 1, 'owner sees own session only');
SELECT is((SELECT count(*)::int FROM public.entries), 1, 'owner sees own entry');
SELECT is((SELECT count(*)::int FROM public.sets), 1, 'owner sees own set');
SELECT is(
  (SELECT array_agg(exercise_id) FROM public.exercise_settings),
  ARRAY['a1000000-0000-0000-0000-000000000001'::uuid], 'owner sees only own rest settings'
);

SELECT lives_ok(
  $$ INSERT INTO public.exercises (id, user_id, name, type)
     VALUES ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Own Row', 'bodyweight') $$,
  'owner inserts an exercise'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercise_muscle_groups (exercise_id, muscle, role)
     VALUES ('a1000000-0000-0000-0000-000000000002', 'core', 'primary') $$,
  'owner inserts a muscle group on an own exercise'
);
SELECT lives_ok(
  $$ INSERT INTO public.routines (id, user_id, name)
     VALUES ('b1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Routine Two') $$,
  'owner inserts a routine'
);
SELECT lives_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000002', 1,
             'c0000000-0000-0000-0000-000000000001') $$,
  'owner inserts a routine item that uses a catalog exercise'
);
SELECT lives_ok(
  $$ INSERT INTO public.sessions (id, user_id, routine_id, completed_at, time_zone)
     VALUES ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
             'b1000000-0000-0000-0000-000000000002', now(), 'Europe/Madrid') $$,
  'owner inserts a session started from an own routine'
);
SELECT lives_ok(
  $$ INSERT INTO public.entries (id, user_id, session_id, position, exercise_id, status)
     VALUES ('e1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
             'd1000000-0000-0000-0000-000000000002', 1, 'c0000000-0000-0000-0000-000000000001', 'done') $$,
  'owner inserts an entry'
);
SELECT lives_ok(
  $$ INSERT INTO public.sets (id, user_id, entry_id, position, source, reps)
     VALUES ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
             'e1000000-0000-0000-0000-000000000002', 1, 'manual', 10) $$,
  'owner inserts a set'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercise_settings (exercise_id, rest_seconds)
     VALUES ('c0000000-0000-0000-0000-000000000001', 45) $$,
  'owner saves a rest setting for a catalogue exercise without user_id (defaults to the caller)'
);
SELECT results_eq(
  $$ INSERT INTO public.exercise_settings (exercise_id, rest_enabled, rest_seconds)
     VALUES ('c0000000-0000-0000-0000-000000000001', false, 45)
     ON CONFLICT (user_id, exercise_id) DO UPDATE SET rest_enabled = EXCLUDED.rest_enabled
     RETURNING user_id, rest_enabled $$,
  $$ VALUES ('00000000-0000-0000-0000-000000000001'::uuid, false) $$,
  'owner upserts own rest setting for a catalogue exercise'
);

SELECT isnt_empty($$ UPDATE public.users SET weight_unit = 'lb' RETURNING id $$, 'owner updates own profile');
SELECT isnt_empty($$ UPDATE public.exercises SET name = 'Renamed' WHERE id = 'a1000000-0000-0000-0000-000000000002' RETURNING id $$, 'owner updates own exercise');
SELECT isnt_empty($$ UPDATE public.routines SET name = 'Renamed' RETURNING id $$, 'owner updates own routines');
SELECT isnt_empty($$ UPDATE public.routine_items SET notes = 'n' RETURNING id $$, 'owner updates own routine items');
SELECT isnt_empty($$ UPDATE public.sessions SET notes = 'n' RETURNING id $$, 'owner updates own sessions');
SELECT isnt_empty($$ UPDATE public.entries SET notes = 'n' RETURNING id $$, 'owner updates own entries');
SELECT isnt_empty($$ UPDATE public.sets SET rir = 2 RETURNING id $$, 'owner updates own sets');
SELECT isnt_empty($$ UPDATE public.exercise_settings SET rest_seconds = rest_seconds + 10 RETURNING exercise_id $$, 'owner updates own rest settings');

SELECT isnt_empty($$ DELETE FROM public.sets WHERE id = 'f1000000-0000-0000-0000-000000000002' RETURNING id $$, 'owner deletes own set');
SELECT isnt_empty($$ DELETE FROM public.sessions WHERE id = 'd1000000-0000-0000-0000-000000000002' RETURNING id $$, 'owner deletes own session');
SELECT isnt_empty($$ DELETE FROM public.routines WHERE id = 'b1000000-0000-0000-0000-000000000002' RETURNING id $$, 'owner deletes own routine');
SELECT isnt_empty($$ DELETE FROM public.exercise_muscle_groups WHERE exercise_id = 'a1000000-0000-0000-0000-000000000002' RETURNING id $$, 'owner deletes own muscle group');
SELECT isnt_empty($$ DELETE FROM public.exercise_settings WHERE exercise_id = 'c0000000-0000-0000-0000-000000000001' RETURNING exercise_id $$, 'owner deletes own rest setting');
SELECT isnt_empty($$ DELETE FROM public.exercises WHERE id = 'a1000000-0000-0000-0000-000000000002' RETURNING id $$, 'owner deletes own exercise');

RESET role;

SELECT is(
  (SELECT array_agg(rest_seconds ORDER BY exercise_id) FROM public.exercise_settings
    WHERE user_id = '00000000-0000-0000-0000-000000000002'),
  ARRAY[60, 75], 'owner''s update left user two''s rest settings unchanged'
);

-- ===============================================================
-- Other user: user two
-- ===============================================================
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';

SELECT is((SELECT count(*)::int FROM public.users WHERE id = '00000000-0000-0000-0000-000000000001'), 0, 'other user cannot see the profile');
SELECT is((SELECT count(*)::int FROM public.exercises WHERE id = 'a1000000-0000-0000-0000-000000000001'), 0, 'other user cannot see a private exercise');
SELECT is((SELECT count(*)::int FROM public.exercises WHERE id = 'c0000000-0000-0000-0000-000000000001'), 1, 'other user sees catalog exercises');
SELECT is((SELECT count(*)::int FROM public.exercise_muscle_groups WHERE exercise_id = 'a1000000-0000-0000-0000-000000000001'), 0, 'other user cannot see muscle groups of a private exercise');
SELECT is((SELECT count(*)::int FROM public.routines WHERE user_id = '00000000-0000-0000-0000-000000000001'), 0, 'other user sees no routines');
SELECT is((SELECT count(*)::int FROM public.routine_items), 0, 'other user sees no routine items');
SELECT is((SELECT count(*)::int FROM public.sessions WHERE user_id = '00000000-0000-0000-0000-000000000001'), 0, 'other user sees no sessions');
SELECT is((SELECT count(*)::int FROM public.entries), 0, 'other user sees no entries');
SELECT is((SELECT count(*)::int FROM public.sets), 0, 'other user sees no sets');
SELECT is(
  (SELECT count(*)::int FROM public.exercise_settings WHERE user_id = '00000000-0000-0000-0000-000000000001'),
  0, 'other user sees no rest settings of user one'
);

-- Writing rows on behalf of user one
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type) VALUES ('00000000-0000-0000-0000-000000000001', 'x', 'strength') $$,
  '42501', NULL, 'other user cannot insert an exercise for user one'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type) VALUES (NULL, 'x', 'strength') $$,
  '42501', NULL, 'signed-in users cannot add catalog exercises'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_muscle_groups (exercise_id, muscle, role)
     VALUES ('a1000000-0000-0000-0000-000000000001', 'back', 'secondary') $$,
  '42501', NULL, 'other user cannot add muscle groups to a private exercise'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_muscle_groups (exercise_id, muscle, role)
     VALUES ('c0000000-0000-0000-0000-000000000001', 'glutes', 'secondary') $$,
  '42501', NULL, 'signed-in users cannot add muscle groups to catalog exercises'
);
SELECT throws_ok(
  $$ INSERT INTO public.routines (user_id, name) VALUES ('00000000-0000-0000-0000-000000000001', 'x') $$,
  '42501', NULL, 'other user cannot insert a routine for user one'
);
SELECT throws_ok(
  $$ INSERT INTO public.sessions (user_id, completed_at, time_zone) VALUES ('00000000-0000-0000-0000-000000000001', now(), 'UTC') $$,
  '42501', NULL, 'other user cannot insert a session for user one'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_settings (user_id, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'other user cannot save a rest setting for user one'
);

SELECT throws_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 9,
             'c0000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'other user cannot insert a routine item as user one'
);
SELECT throws_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 9,
             'c0000000-0000-0000-0000-000000000001', 'skipped') $$,
  '42501', NULL, 'other user cannot insert an entry as user one'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 9, 'manual', 1) $$,
  '42501', NULL, 'other user cannot insert a set as user one'
);

-- Own rows that point at user one's rows (FKs bypass RLS, composite FKs stop it)
SELECT throws_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 9,
             'c0000000-0000-0000-0000-000000000001') $$,
  '23503', NULL, 'other user cannot add items to user one''s routine'
);
SELECT throws_ok(
  $$ INSERT INTO public.sessions (user_id, routine_id, completed_at, time_zone)
     VALUES ('00000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', now(), 'UTC') $$,
  '23503', NULL, 'other user cannot start a session from user one''s routine'
);
SELECT throws_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 9,
             'c0000000-0000-0000-0000-000000000001', 'skipped') $$,
  '23503', NULL, 'other user cannot add entries to user one''s session'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps)
     VALUES ('00000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 9, 'manual', 1) $$,
  '23503', NULL, 'other user cannot add sets to user one''s entry'
);
SELECT throws_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001', 1,
             'a1000000-0000-0000-0000-000000000001', 'skipped') $$,
  '42501', NULL, 'other user cannot log user one''s private exercise'
);
SELECT throws_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status, replaced_exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001', 1,
             'c0000000-0000-0000-0000-000000000001', 'skipped', 'a1000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'other user cannot name user one''s private exercise as replaced'
);

SELECT throws_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001', 1,
             'a1000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'other user cannot plan user one''s private exercise'
);

SELECT throws_ok(
  $$ INSERT INTO public.exercise_settings (exercise_id) VALUES ('a1000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'other user cannot save a rest setting for user one''s private exercise'
);
SELECT throws_ok(
  $$ UPDATE public.exercise_settings SET exercise_id = 'a1000000-0000-0000-0000-000000000001'
     WHERE exercise_id = 'a2000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'other user cannot move a rest setting onto user one''s private exercise'
);
SELECT throws_ok(
  $$ UPDATE public.exercise_settings SET user_id = '00000000-0000-0000-0000-000000000001'
     WHERE exercise_id = 'a2000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'other user cannot hand a rest setting over to user one'
);

-- Updates and deletes of user one's rows affect nothing
SELECT is_empty($$ UPDATE public.exercises SET name = 'x' WHERE id = 'a1000000-0000-0000-0000-000000000001' RETURNING id $$, 'other user cannot update a private exercise');
SELECT is_empty($$ UPDATE public.exercises SET name = 'x' WHERE id = 'c0000000-0000-0000-0000-000000000001' RETURNING id $$, 'signed-in users cannot update catalog exercises');
SELECT is_empty($$ DELETE FROM public.exercises WHERE id = 'c0000000-0000-0000-0000-000000000001' RETURNING id $$, 'signed-in users cannot delete catalog exercises');
SELECT is_empty($$ UPDATE public.sessions SET notes = 'x' WHERE id = 'd1000000-0000-0000-0000-000000000001' RETURNING id $$, 'other user cannot update user one''s session');
SELECT is_empty($$ DELETE FROM public.sets RETURNING id $$, 'other user cannot delete user one''s sets');
SELECT is_empty($$ DELETE FROM public.routines WHERE user_id = '00000000-0000-0000-0000-000000000001' RETURNING id $$, 'other user cannot delete user one''s routines');
SELECT is_empty($$ UPDATE public.exercise_settings SET rest_enabled = false WHERE user_id = '00000000-0000-0000-0000-000000000001' RETURNING exercise_id $$, 'other user cannot update user one''s rest settings');
SELECT is_empty($$ DELETE FROM public.exercise_settings WHERE user_id = '00000000-0000-0000-0000-000000000001' RETURNING exercise_id $$, 'other user cannot delete user one''s rest settings');

-- An own row cannot be handed over to user one
SELECT throws_ok(
  $$ UPDATE public.sessions SET user_id = '00000000-0000-0000-0000-000000000001'
     WHERE id = 'd2000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'user_id cannot be reassigned to another user'
);

RESET role;

-- ===============================================================
-- Anonymous callers have no table access
-- ===============================================================
SET LOCAL role = anon;
SELECT throws_ok($$ SELECT 1 FROM public.exercises $$, '42501', NULL, 'anon cannot read exercises');
SELECT throws_ok($$ SELECT 1 FROM public.sessions $$, '42501', NULL, 'anon cannot read sessions');
RESET role;

-- ===============================================================
-- Curated catalogue and private imported exercises
-- ===============================================================
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES (NULL, 'Machine Row', 'strength', 'machines-atlas', 'm-100') $$,
  '42501', NULL, 'signed-in users cannot add a catalogue exercise with an externalRef'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercises (id, user_id, name, type, equipment, external_provider, external_id)
     VALUES ('a1000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000001', 'Machine Row', 'strength', 'connected_machine', 'machines-atlas', 'm-100') $$,
  'user one imports a provider exercise as a private row'
);
SELECT results_eq(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Machine Row v2', 'strength', 'machines-atlas', 'm-100')
     ON CONFLICT (user_id, external_provider, external_id) DO UPDATE SET name = EXCLUDED.name
     RETURNING id $$,
  $$ VALUES ('a1000000-0000-0000-0000-000000000100'::uuid) $$,
  'upserting an imported exercise on its externalRef returns the existing id'
);
SELECT throws_ok(
  $$ UPDATE public.exercises SET user_id = NULL WHERE id = 'a1000000-0000-0000-0000-000000000100' $$,
  '42501', NULL, 'a user cannot move an imported exercise into the catalogue'
);
SELECT throws_ok(
  $$ UPDATE public.exercises SET user_id = NULL, external_provider = NULL, external_id = NULL
     WHERE id = 'a1000000-0000-0000-0000-000000000100' $$,
  '42501', NULL, 'a user cannot move an exercise into the catalogue even without its externalRef'
);
RESET role;

SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT lives_ok(
  $$ INSERT INTO public.exercises (id, user_id, name, type, external_provider, external_id)
     VALUES ('a2000000-0000-0000-0000-000000000100', '00000000-0000-0000-0000-000000000002', 'Row Machine', 'strength', 'machines-atlas', 'm-100') $$,
  'user two imports the same provider exercise as their own private row'
);
SELECT is(
  (SELECT array_agg(user_id) FROM public.exercises WHERE external_provider = 'machines-atlas' AND external_id = 'm-100'),
  ARRAY['00000000-0000-0000-0000-000000000002'::uuid], 'user two sees only their own copy of the provider exercise'
);
SELECT throws_ok(
  $$ UPDATE public.exercises SET user_id = '00000000-0000-0000-0000-000000000001' WHERE id = 'a2000000-0000-0000-0000-000000000100' $$,
  '42501', NULL, 'user two cannot hand an imported exercise over to user one'
);
-- Keys are random and owned by the receiver. Reusing another user's key is a
-- primary key conflict: it reveals only that the key exists, nothing of the row.
SELECT throws_ok(
  $$ INSERT INTO public.sessions (id, user_id, completed_at, time_zone)
     VALUES ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', now(), 'UTC') $$,
  '23505', NULL, 'an insert with another user''s primary key fails'
);
RESET role;

-- User one has logged the catalogue squat in their session. An entry of user
-- two pointing at that session must fail on the foreign key, without revealing
-- what user one's session holds.
INSERT INTO public.entries (user_id, session_id, position, exercise_id, status) VALUES
  ('00000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 2, 'c0000000-0000-0000-0000-000000000001', 'done');
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT throws_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 9, 'c0000000-0000-0000-0000-000000000001', 'done') $$,
  '23503', NULL, 'an entry in another user''s session fails on the foreign key, not on its done exercises'
);
RESET role;

-- The service role curates the catalogue: rows without an externalRef only.
SET LOCAL role = service_role;
SELECT lives_ok(
  $$ INSERT INTO public.exercises (user_id, name, type) VALUES (NULL, 'Curated Deadlift', 'strength') $$,
  'the service role adds a catalogue exercise without an externalRef'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES (NULL, 'Curated Row', 'strength', 'machines-atlas', 'm-200') $$,
  '23514', 'new row for relation "exercises" violates check constraint "exercises_catalogue_has_no_external_ref"',
  'not even the service role can give a catalogue exercise an externalRef'
);
SELECT throws_ok(
  $$ UPDATE public.exercises SET user_id = NULL WHERE id = 'a1000000-0000-0000-0000-000000000100' $$,
  '23514', 'new row for relation "exercises" violates check constraint "exercises_catalogue_has_no_external_ref"',
  'not even the service role can move an imported exercise into the catalogue'
);
RESET role;

-- ===============================================================
-- Account deletion removes all of the user's data
-- ===============================================================
SELECT throws_ok(
  $$ DELETE FROM public.exercises WHERE id = 'a1000000-0000-0000-0000-000000000001' $$,
  '23503', NULL, 'an exercise that history uses cannot be deleted on its own'
);
SELECT lives_ok(
  $$ DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000001' $$,
  'deleting an account with routines, sessions and private exercises succeeds'
);
SELECT is(
  (SELECT count(*)::int FROM public.exercises WHERE user_id = '00000000-0000-0000-0000-000000000001')
  + (SELECT count(*)::int FROM public.routines WHERE user_id = '00000000-0000-0000-0000-000000000001')
  + (SELECT count(*)::int FROM public.sessions WHERE user_id = '00000000-0000-0000-0000-000000000001')
  + (SELECT count(*)::int FROM public.entries WHERE user_id = '00000000-0000-0000-0000-000000000001')
  + (SELECT count(*)::int FROM public.sets WHERE user_id = '00000000-0000-0000-0000-000000000001')
  + (SELECT count(*)::int FROM public.exercise_settings WHERE user_id = '00000000-0000-0000-0000-000000000001'),
  0, 'no rows of the deleted account remain'
);

SELECT * FROM finish();
ROLLBACK;
