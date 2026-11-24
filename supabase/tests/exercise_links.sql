-- pgTAP: personal related links of an exercise (S10, AC5).
-- A user's links of a catalogue or own exercise: only their owner reads or
-- writes them, another user and anon never do. title and source are not
-- empty, the url is https, position starts at 1. Every deleted link, also with
-- its exercise, leaves its owner a tombstone; writing it again clears it.
BEGIN;

SELECT plan(64);

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
  ('c0000000-0000-0000-0000-000000000002', NULL, 'Catalog Press', 'strength'),
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Own Lunge', 'strength'),
  ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Own Row', 'strength'),
  ('a2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 'Other Lunge', 'strength');

INSERT INTO public.exercise_links (id, user_id, exercise_id, title, url, source, position, created_at, updated_at) VALUES
  ('71000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000001', 'Squat depth', 'https://video.example.test/watch?v=aaa111', 'video.example.test', 1,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');

INSERT INTO public.exercise_links (id, user_id, exercise_id, title, url, source, position) VALUES
  ('71000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000001', 'Lunge article', 'https://blog.example.test/lunge', 'blog.example.test', 1),
  ('71000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
   'a1000000-0000-0000-0000-000000000002', 'Row cues', 'https://blog.example.test/row', 'blog.example.test', 1),
  ('71000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000002', 'Press grip', 'https://blog.example.test/press', 'blog.example.test', 1),
  ('72000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002',
   'c0000000-0000-0000-0000-000000000001', 'Other squat', 'https://video.example.test/watch?v=bbb222', 'video.example.test', 1),
  ('72000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000002',
   'a2000000-0000-0000-0000-000000000001', 'Other lunge', 'https://blog.example.test/other', 'blog.example.test', 1);

CREATE FUNCTION pg_temp.tombstones_of(owner uuid) RETURNS text[]
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT coalesce(array_agg(table_name || ':' || row_id ORDER BY table_name COLLATE "C", row_id), '{}')
  FROM public.tombstones WHERE user_id = owner
$$;

-- ---------------------------------------------------------------
-- Shape
-- ---------------------------------------------------------------
SELECT has_table('public', 'exercise_links', 'exercise_links exists');
SELECT col_is_pk('public', 'exercise_links', 'id', 'exercise_links key is id');
SELECT col_default_is('public', 'exercise_links', 'id', 'gen_random_uuid()', 'exercise_links.id defaults to a new uuid');
SELECT col_default_is('public', 'exercise_links', 'user_id', 'auth.uid()', 'exercise_links.user_id defaults to the caller');
SELECT fk_ok('public', 'exercise_links', 'user_id', 'public', 'users', 'id', 'exercise_links.user_id references users');
SELECT fk_ok('public', 'exercise_links', 'exercise_id', 'public', 'exercises', 'id', 'exercise_links.exercise_id references exercises');
SELECT columns_are(
  'public', 'exercise_links',
  ARRAY['id', 'user_id', 'exercise_id', 'title', 'url', 'source', 'position', 'created_at', 'updated_at'],
  'exercise_links has exactly its columns'
);
SELECT ok(
  (SELECT bool_and(attnotnull) FROM pg_attribute
    WHERE attrelid = 'public.exercise_links'::regclass AND attnum > 0 AND NOT attisdropped),
  'every exercise_links column is never null'
);
SELECT col_type_is('public', 'exercise_links', 'position', 'integer', 'exercise_links.position is an integer');
SELECT col_default_is('public', 'exercise_links', 'position', '1', 'exercise_links.position defaults to 1');
SELECT has_index('public', 'exercise_links', 'exercise_links_exercise_id_idx', 'exercise_links.exercise_id is indexed for the cascade');
SELECT has_index('public', 'exercise_links', 'exercise_links_user_id_idx', 'exercise_links.user_id is indexed for row-level security');
SELECT has_trigger('public', 'exercise_links', 'set_updated_at', 'exercise_links bumps updated_at on update');
SELECT has_trigger('public', 'exercise_links', 'record_tombstones', 'exercise link deletes record tombstones');
SELECT has_trigger('public', 'exercise_links', 'clear_tombstones', 'exercise link inserts clear tombstones');
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.exercise_links'::regclass),
  'exercise_links has RLS enabled'
);
SELECT policies_are(
  'public', 'exercise_links',
  ARRAY['exercise_links: select own', 'exercise_links: insert own',
        'exercise_links: update own', 'exercise_links: delete own'],
  'exercise_links has exactly the owner policies'
);
SELECT ok(
  NOT (has_table_privilege('anon', 'public.exercise_links', 'SELECT')
       OR has_table_privilege('anon', 'public.exercise_links', 'INSERT')
       OR has_table_privilege('anon', 'public.exercise_links', 'UPDATE')
       OR has_table_privilege('anon', 'public.exercise_links', 'DELETE')),
  'anon has no DML on exercise_links'
);

-- ---------------------------------------------------------------
-- Constraints
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'Plain', 'http://blog.example.test/plain', 'blog.example.test') $$,
  '23514', NULL, 'a link that is not https is refused'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'Spaced', 'https://blog.example.test/a b', 'blog.example.test') $$,
  '23514', NULL, 'a url with a space is refused'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'Bare', 'https://', 'blog.example.test') $$,
  '23514', NULL, 'a url with no address after the scheme is refused'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             '  ', 'https://blog.example.test/blank', 'blog.example.test') $$,
  '23514', NULL, 'a blank title is refused'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'No source', 'https://blog.example.test/nosource', '') $$,
  '23514', NULL, 'an empty source is refused'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source, position)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'Zero', 'https://blog.example.test/zero', 'blog.example.test', 0) $$,
  '23514', NULL, 'a position below 1 is refused'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-00000000ffff',
             'Nowhere', 'https://blog.example.test/nowhere', 'blog.example.test') $$,
  '23503', NULL, 'a link of an exercise that does not exist is refused'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'No url', 'blog.example.test') $$,
  '23502', NULL, 'a link without url is refused'
);

-- ---------------------------------------------------------------
-- Owner: user one
-- ---------------------------------------------------------------
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

SELECT is(
  (SELECT array_agg(id ORDER BY id) FROM public.exercise_links),
  ARRAY['71000000-0000-0000-0000-000000000001', '71000000-0000-0000-0000-000000000002',
        '71000000-0000-0000-0000-000000000003', '71000000-0000-0000-0000-000000000004']::uuid[],
  'owner reads only own links, on catalogue and own exercises'
);
SELECT results_eq(
  $$ INSERT INTO public.exercise_links (id, exercise_id, title, url, source, position)
     VALUES ('71000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000001',
             'Squat cues', 'https://blog.example.test/squat', 'blog.example.test', 2)
     RETURNING user_id $$,
  $$ VALUES ('00000000-0000-0000-0000-000000000001'::uuid) $$,
  'owner adds a link to a catalogue exercise without user_id (defaults to the caller)'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercise_links (id, user_id, exercise_id, title, url, source, position)
     VALUES ('71000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001',
             'a1000000-0000-0000-0000-000000000001', 'Lunge video', 'https://video.example.test/watch?v=ccc333',
             'video.example.test', 2) $$,
  'owner adds a link to an own exercise'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'Lunge video again', 'https://video.example.test/watch?v=ccc333', 'video.example.test') $$,
  'the server accepts the same url twice (two offline devices cannot wedge the push)'
);
SELECT results_eq(
  $$ UPDATE public.exercise_links SET title = 'Squat depth, explained'
     WHERE id = '71000000-0000-0000-0000-000000000001' RETURNING title $$,
  $$ VALUES ('Squat depth, explained') $$,
  'owner renames own link'
);
SELECT ok(
  (SELECT updated_at > '2026-01-01T00:00:00Z' FROM public.exercise_links
    WHERE id = '71000000-0000-0000-0000-000000000001'),
  'renaming a link bumps its updated_at'
);
SELECT is((SELECT count(*)::int FROM public.tombstones), 0, 'adding and renaming links records no tombstone');

SELECT isnt_empty(
  $$ DELETE FROM public.exercise_links WHERE id = '71000000-0000-0000-0000-000000000002' RETURNING id $$,
  'owner deletes own link'
);
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'),
  ARRAY['exercise_links:71000000-0000-0000-0000-000000000002'],
  'deleting a link records a tombstone of its owner'
);

-- Written again under the same id (a device that kept it pushes it back).
INSERT INTO public.exercise_links (id, exercise_id, title, url, source)
VALUES ('71000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000001',
        'Lunge article', 'https://blog.example.test/lunge', 'blog.example.test');
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'), '{}'::text[],
  'a link written again clears its tombstone'
);

-- Deleted with its own exercise: its tombstone too, next to the exercise's.
DELETE FROM public.exercises WHERE id = 'a1000000-0000-0000-0000-000000000002';
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'),
  ARRAY['exercise_links:71000000-0000-0000-0000-000000000003', 'exercises:a1000000-0000-0000-0000-000000000002'],
  'a link deleted with its own exercise leaves its owner a tombstone'
);

-- The owner cannot move a link to an exercise they cannot see, nor give it away.
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (exercise_id, title, url, source)
     VALUES ('a2000000-0000-0000-0000-000000000001', 'Sneak', 'https://blog.example.test/sneak', 'blog.example.test') $$,
  '42501', NULL, 'owner cannot add a link to another user''s exercise'
);
SELECT throws_ok(
  $$ UPDATE public.exercise_links SET exercise_id = 'a2000000-0000-0000-0000-000000000001'
     WHERE id = '71000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'owner cannot move a link to another user''s exercise'
);
SELECT throws_ok(
  $$ UPDATE public.exercise_links SET user_id = '00000000-0000-0000-0000-000000000002'
     WHERE id = '71000000-0000-0000-0000-000000000001' $$,
  '42501', NULL, 'owner cannot give a link to another user'
);

-- ---------------------------------------------------------------
-- Another user: user two
-- ---------------------------------------------------------------
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';

SELECT is(
  (SELECT array_agg(id ORDER BY id) FROM public.exercise_links),
  ARRAY['72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-000000000002']::uuid[],
  'other user reads only their own links, not user one''s'
);
SELECT is_empty(
  $$ SELECT 1 FROM public.exercise_links WHERE user_id = '00000000-0000-0000-0000-000000000001' $$,
  'other user cannot read user one''s links, even on a shared catalogue exercise'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001',
             'Planted', 'https://blog.example.test/planted', 'blog.example.test') $$,
  '42501', NULL, 'other user cannot add a link for user one'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (exercise_id, title, url, source)
     VALUES ('a1000000-0000-0000-0000-000000000001', 'Peek', 'https://blog.example.test/peek', 'blog.example.test') $$,
  '42501', NULL, 'other user cannot add a link to user one''s exercise'
);
SELECT is_empty(
  $$ UPDATE public.exercise_links SET title = 'Taken' WHERE user_id = '00000000-0000-0000-0000-000000000001' RETURNING id $$,
  'other user cannot rename user one''s links'
);
SELECT is_empty(
  $$ DELETE FROM public.exercise_links WHERE user_id = '00000000-0000-0000-0000-000000000001' RETURNING id $$,
  'other user cannot delete user one''s links'
);
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000002'), '{}'::text[],
  'the refused delete records no tombstone'
);

-- Unfiltered writes: with no WHERE the select policy hides nothing the
-- update and delete policies would not, so only they keep user one's rows.
-- user one's links and tombstones as they are now, read as postgres.
RESET role;
CREATE TEMP TABLE one_links AS
  SELECT id, user_id, exercise_id, title FROM public.exercise_links
  WHERE user_id = '00000000-0000-0000-0000-000000000001';
CREATE TEMP TABLE one_tombstones AS
  SELECT id FROM public.tombstones WHERE user_id = '00000000-0000-0000-0000-000000000001';
SET LOCAL role = authenticated;

SAVEPOINT unfiltered_update;
UPDATE public.exercise_links
SET user_id = '00000000-0000-0000-0000-000000000002', exercise_id = 'c0000000-0000-0000-0000-000000000002';
RESET role;
SELECT set_eq(
  $$ SELECT id, user_id, exercise_id, title FROM public.exercise_links WHERE id IN (SELECT id FROM one_links) $$,
  $$ SELECT id, user_id, exercise_id, title FROM one_links $$,
  'other user''s unfiltered update changes none of user one''s links'
);
ROLLBACK TO SAVEPOINT unfiltered_update;

SAVEPOINT unfiltered_delete;
DELETE FROM public.exercise_links;
RESET role;
SELECT set_eq(
  $$ SELECT id, user_id, exercise_id, title FROM public.exercise_links WHERE user_id = '00000000-0000-0000-0000-000000000001' $$,
  $$ SELECT id, user_id, exercise_id, title FROM one_links $$,
  'other user''s unfiltered delete leaves user one''s links'
);
SELECT set_eq(
  $$ SELECT id FROM public.tombstones WHERE user_id = '00000000-0000-0000-0000-000000000001' $$,
  $$ SELECT id FROM one_tombstones $$,
  'and records no tombstone of them'
);
ROLLBACK TO SAVEPOINT unfiltered_delete;

-- The owner cannot give all their links away in one unfiltered update.
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
SELECT throws_ok(
  $$ UPDATE public.exercise_links SET user_id = '00000000-0000-0000-0000-000000000002' $$,
  '42501', NULL, 'owner''s unfiltered update giving the links to another user is refused'
);
RESET role;
SELECT set_eq(
  $$ SELECT id, user_id, exercise_id, title FROM public.exercise_links WHERE id IN (SELECT id FROM one_links) $$,
  $$ SELECT id, user_id, exercise_id, title FROM one_links $$,
  'and every link keeps its owner'
);
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';

-- Another user reusing a deleted id clears nothing of user one's.
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
DELETE FROM public.exercise_links WHERE id = '71000000-0000-0000-0000-000000000004';
SET LOCAL "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
SELECT lives_ok(
  $$ INSERT INTO public.exercise_links (id, exercise_id, title, url, source)
     VALUES ('71000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000002',
             'Reused id', 'https://blog.example.test/reused', 'blog.example.test') $$,
  'other user writes a link under an id user one deleted'
);
SELECT ok(
  'exercise_links:71000000-0000-0000-0000-000000000004' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'another user reusing the id does not clear user one''s tombstone'
);
SELECT is_empty(
  $$ SELECT 1 FROM public.tombstones WHERE user_id = '00000000-0000-0000-0000-000000000001' $$,
  'other user cannot read user one''s tombstones'
);

-- ---------------------------------------------------------------
-- The catalogue exercise is removed (service role)
-- ---------------------------------------------------------------
RESET role;
SET LOCAL role = service_role;
DELETE FROM public.exercises WHERE id = 'c0000000-0000-0000-0000-000000000001';
RESET role;
SELECT ok(
  'exercise_links:71000000-0000-0000-0000-000000000001' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001'))
  AND 'exercise_links:71000000-0000-0000-0000-000000000005' = ANY (pg_temp.tombstones_of('00000000-0000-0000-0000-000000000001')),
  'the links of a removed catalogue exercise leave user one tombstones'
);
SELECT is(
  pg_temp.tombstones_of('00000000-0000-0000-0000-000000000002'),
  ARRAY['exercise_links:72000000-0000-0000-0000-000000000001'],
  'and user two a tombstone of their own link only'
);
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE table_name = 'exercises' AND row_id = 'c0000000-0000-0000-0000-000000000001'), 0,
  'the catalogue exercise itself leaves no tombstone'
);

-- ---------------------------------------------------------------
-- Account deletion
-- ---------------------------------------------------------------
DELETE FROM auth.users WHERE id = '00000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM public.exercise_links WHERE user_id = '00000000-0000-0000-0000-000000000002'), 0,
  'deleting an account deletes its links'
);
SELECT is(
  (SELECT count(*)::int FROM public.tombstones WHERE user_id = '00000000-0000-0000-0000-000000000002'), 0,
  'and keeps no tombstones of them'
);
SELECT is(
  (SELECT count(*)::int FROM public.exercise_links WHERE user_id = '00000000-0000-0000-0000-000000000001'), 3,
  'user one''s links stay'
);

-- ---------------------------------------------------------------
-- anon
-- ---------------------------------------------------------------
SET LOCAL role = anon;
SET LOCAL "request.jwt.claims" = '{"role":"anon"}';
SELECT throws_ok($$ SELECT 1 FROM public.exercise_links $$, '42501', NULL, 'anon cannot read links');
SELECT throws_ok(
  $$ INSERT INTO public.exercise_links (user_id, exercise_id, title, url, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001',
             'Anon', 'https://blog.example.test/anon', 'blog.example.test') $$,
  '42501', NULL, 'anon cannot add links'
);
SELECT throws_ok($$ DELETE FROM public.exercise_links $$, '42501', NULL, 'anon cannot delete links');

SELECT * FROM finish();
ROLLBACK;
