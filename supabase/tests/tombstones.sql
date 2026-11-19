-- pgTAP: server-side tombstones for the sync (issue #135, S11).
-- Deleting a user-owned exercise, routine, session, entry or set, by any client
-- and through any cascade, records a tombstone of its owner, which the app
-- pulls with the same (updated_at, id) cursor as the rows. Writing the row
-- again under the same id clears it. Owners read their own tombstones; nobody
-- writes them through the API.
BEGIN;

SELECT plan(35);

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
  ('c0000000-0000-0000-0000-000000000002', NULL, 'Catalog Row', 'strength'),
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Used One', 'strength'),
  ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Unused One', 'strength'),
  ('a2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Used Two', 'strength');

INSERT INTO public.routines (id, user_id, name) VALUES
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Routine One');

INSERT INTO public.routine_items (id, user_id, routine_id, position, exercise_id) VALUES
  ('b1100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001', 1, 'c0000000-0000-0000-0000-000000000001');

INSERT INTO public.sessions (id, user_id, routine_id, completed_at, time_zone) VALUES
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001', now(), 'Europe/Madrid'),
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', NULL, now(), 'UTC'),
  ('d2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', NULL, now(), 'UTC');

INSERT INTO public.entries (id, user_id, session_id, position, exercise_id, status) VALUES
  ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'd1000000-0000-0000-0000-000000000001', 1, 'a1000000-0000-0000-0000-000000000001', 'done'),
  ('e1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'd1000000-0000-0000-0000-000000000002', 1, 'c0000000-0000-0000-0000-000000000001', 'done'),
  ('e2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002',
   'd2000000-0000-0000-0000-000000000001', 1, 'a2000000-0000-0000-0000-000000000001', 'done');

INSERT INTO public.sets (id, user_id, entry_id, position, source, reps) VALUES
  ('f1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000001', 1, 'manual', 8),
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000001', 2, 'manual', 6),
  ('f1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000002', 1, 'manual', 5),
  ('f2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002',
   'e2000000-0000-0000-0000-000000000001', 1, 'manual', 10);

-- Tombstones of one user, as `table:row` text, for compact comparisons.
CREATE FUNCTION pg_temp.tombstones_of(owner uuid) RETURNS text[]
LANGUAGE sql AS $$
  SELECT coalesce(array_agg(table_name || ':' || row_id ORDER BY table_name, row_id), '{}')
  FROM public.tombstones WHERE user_id = owner
$$;

-- ---------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------
SELECT has_table('public', 'tombstones', 'tombstones exists');
SELECT col_is_pk('public', 'tombstones', 'id', 'a tombstone has its own id, the cursor''s tie-break');
SELECT col_not_null('public', 'tombstones', 'updated_at', 'tombstones.updated_at is never null');
SELECT col_not_null('public', 'tombstones', 'row_id', 'tombstones.row_id is never null');
SELECT fk_ok('public', 'tombstones', 'user_id', 'public', 'users', 'id', 'tombstones.user_id references users');
SELECT has_index('public', 'tombstones', 'tombstones_user_cursor_idx', 'tombstones are indexed for the cursor');

-- ---------------------------------------------------------------
-- The owner deletes rows through the API
-- ---------------------------------------------------------------
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'), '{}', 'no tombstone before any delete');

UPDATE public.sets SET reps = 9 WHERE id = 'f1000000-0000-0000-0000-000000000001';
SELECT is((SELECT count(*)::int FROM public.tombstones), 0, 'an update records no tombstone');

DELETE FROM public.sets WHERE id = 'f1000000-0000-0000-0000-000000000002';
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'),
  ARRAY['sets:f1000000-0000-0000-0000-000000000002'],
  'deleting a set records its tombstone'
);
SELECT ok(
  (SELECT updated_at IS NOT NULL AND id IS NOT NULL FROM public.tombstones
    WHERE row_id = 'f1000000-0000-0000-0000-000000000002'),
  'the tombstone carries an id and updated_at for the cursor'
);

DELETE FROM public.sessions WHERE id = 'd1000000-0000-0000-0000-000000000002';
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'),
  ARRAY[
    'entries:e1000000-0000-0000-0000-000000000002',
    'sessions:d1000000-0000-0000-0000-000000000002',
    'sets:f1000000-0000-0000-0000-000000000002',
    'sets:f1000000-0000-0000-0000-000000000003'
  ],
  'deleting a session records it and every entry and set its cascade deleted'
);

DELETE FROM public.routines WHERE id = 'b1000000-0000-0000-0000-000000000001';
SELECT ok(
  'routines:b1000000-0000-0000-0000-000000000001' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'deleting a routine records its tombstone'
);
SELECT ok(
  NOT ('routine_items:b1100000-0000-0000-0000-000000000001' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'))),
  'routine items are not tracked: they follow their routine'
);
SELECT is(
  (SELECT routine_id FROM public.sessions WHERE id = 'd1000000-0000-0000-0000-000000000001'), NULL,
  'a session of the deleted routine keeps its row, without the routine'
);

DELETE FROM public.exercises WHERE id = 'a1000000-0000-0000-0000-000000000002';
SELECT ok(
  'exercises:a1000000-0000-0000-0000-000000000002' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'deleting a user exercise records its tombstone'
);

SELECT is((SELECT count(*)::int FROM public.tombstones), 6, 'the owner reads every tombstone of theirs');

-- Nobody writes tombstones through the API.
SELECT throws_ok(
  $$ INSERT INTO public.tombstones (user_id, table_name, row_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'sessions', 'd1000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'the owner cannot write a tombstone'
);
SELECT throws_ok(
  $$ UPDATE public.tombstones SET updated_at = now() $$,
  '42501', NULL, 'the owner cannot change a tombstone'
);
SELECT throws_ok(
  $$ DELETE FROM public.tombstones $$,
  '42501', NULL, 'the owner cannot delete a tombstone'
);

-- Writing a row again under the same id brings it back: its tombstone goes.
INSERT INTO public.sets (id, user_id, entry_id, position, source, reps) VALUES
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000001', 2, 'manual', 6)
ON CONFLICT (id) DO UPDATE SET reps = EXCLUDED.reps;
SELECT ok(
  NOT ('sets:f1000000-0000-0000-0000-000000000002' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'))),
  'an upsert that inserts the row again clears its tombstone'
);
SELECT is((SELECT count(*)::int FROM public.tombstones), 5, 'only that tombstone went');
INSERT INTO public.sets (id, user_id, entry_id, position, source, reps) VALUES
  ('f1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'e1000000-0000-0000-0000-000000000001', 2, 'manual', 7)
ON CONFLICT (id) DO UPDATE SET reps = EXCLUDED.reps;
SELECT is((SELECT count(*)::int FROM public.tombstones), 5, 'an upsert that updates clears nothing');

-- Deleting it again records a new tombstone.
DELETE FROM public.sets WHERE id = 'f1000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE row_id = 'f1000000-0000-0000-0000-000000000002'), 1,
  'deleting the row again records its tombstone again'
);

-- A delete that reaches no row records nothing.
DELETE FROM public.sessions WHERE id = 'd2000000-0000-0000-0000-000000000001';
SELECT is((SELECT count(*)::int FROM public.tombstones), 6, 'deleting another user''s row reaches nothing');

-- ---------------------------------------------------------------
-- Another user
-- ---------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT is((SELECT count(*)::int FROM public.tombstones), 0, 'another user sees none of the owner''s tombstones');
-- Another user writing a row under an id the owner deleted clears nothing of the owner's.
INSERT INTO public.sessions (id, user_id, completed_at, time_zone) VALUES
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002', now(), 'UTC');
RESET role;
SELECT ok(
  'sessions:d1000000-0000-0000-0000-000000000002' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'another user reusing a deleted id leaves the owner''s tombstone'
);
-- Tidy up as postgres: that session and the tombstone its delete leaves.
DELETE FROM public.sessions WHERE id = 'd1000000-0000-0000-0000-000000000002';
DELETE FROM public.tombstones WHERE user_id = '00000000-0000-0000-0000-000000000002';

SET LOCAL role = anon;
SELECT throws_ok($$ SELECT count(*) FROM public.tombstones $$, '42501', NULL, 'anon cannot read tombstones');
RESET role;

-- ---------------------------------------------------------------
-- Writes outside the app (an importer with the service role)
-- ---------------------------------------------------------------
SET LOCAL role = service_role;
DELETE FROM public.sets WHERE id = 'f2000000-0000-0000-0000-000000000001';
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000002'),
  ARRAY['sets:f2000000-0000-0000-0000-000000000001'],
  'a service-role delete records a tombstone of the row''s owner'
);
DELETE FROM public.exercises WHERE id = 'c0000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE row_id = 'c0000000-0000-0000-0000-000000000002'), 0,
  'deleting a catalogue exercise records no tombstone: it belongs to nobody'
);
SELECT ok(
  has_table_privilege('service_role', 'public.tombstones', 'SELECT')
  AND has_table_privilege('service_role', 'public.tombstones', 'DELETE'),
  'the service role can read and prune tombstones'
);
RESET role;

SELECT ok(
  has_table_privilege('authenticated', 'public.tombstones', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.tombstones', 'INSERT')
  AND NOT has_table_privilege('authenticated', 'public.tombstones', 'UPDATE')
  AND NOT has_table_privilege('authenticated', 'public.tombstones', 'DELETE'),
  'authenticated only reads tombstones'
);
SELECT ok(
  NOT has_table_privilege('anon', 'public.tombstones', 'SELECT'),
  'anon has no privilege on tombstones'
);

-- ---------------------------------------------------------------
-- Account deletion
-- ---------------------------------------------------------------
SELECT lives_ok(
  $$ DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000001' $$,
  'deleting an account with tombstones, sessions and exercises succeeds'
);
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE user_id = '00000000-0000-0000-0000-000000000001'), 0,
  'no tombstone of the deleted account remains'
);
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000002'),
  ARRAY['sets:f2000000-0000-0000-0000-000000000001'],
  'another account''s tombstones are untouched'
);

SELECT * FROM finish();
ROLLBACK;
