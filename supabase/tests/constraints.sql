-- pgTAP: invariants of the training data format enforced in SQL (S1).
-- Each block names the format rule it covers (docs/training-data-format.md).
BEGIN;

SELECT plan(97);

INSERT INTO auth.users (
  id, instance_id, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, role
) VALUES
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
   'one@example.test', '', now(), now(), now(), '{}', '{}', false, 'authenticated'),
  ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000',
   'two@example.test', '', now(), now(), now(), '{}', '{}', false, 'authenticated');

-- Fixtures: one strength, one cardio exercise; one session with a done entry each.
INSERT INTO public.exercises (id, user_id, name, type, equipment) VALUES
  ('a1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Chest Press', 'strength', 'connected_machine'),
  ('a1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'Rowing', 'cardio', 'cardio_machine'),
  ('a1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Plank', 'bodyweight', 'none');

INSERT INTO public.routines (id, user_id, name) VALUES
  ('b1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'Routine');

INSERT INTO public.sessions (id, user_id, started_at, completed_at, time_zone) VALUES
  ('d1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   '2030-03-04T17:00:00Z', '2030-03-04T18:00:00Z', 'Europe/Madrid'),
  ('d1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   NULL, '2030-03-05T18:00:00Z', 'Europe/Madrid');

INSERT INTO public.entries (id, user_id, session_id, position, exercise_id, status) VALUES
  ('e1000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
   'd1000000-0000-0000-0000-000000000001', 1, 'a1000000-0000-0000-0000-000000000001', 'done'),
  ('e1000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001',
   'd1000000-0000-0000-0000-000000000001', 2, 'a1000000-0000-0000-0000-000000000002', 'done'),
  ('e1000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001',
   'd1000000-0000-0000-0000-000000000001', 3, 'a1000000-0000-0000-0000-000000000003', 'skipped');

-- ---------------------------------------------------------------
-- unique-external-ref: unique per provider, kind and user
-- ---------------------------------------------------------------
SELECT lives_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Imported', 'strength', 'machines-atlas', 'ex-1') $$,
  'an imported exercise stores its externalRef'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Again', 'strength', 'machines-atlas', 'ex-1') $$,
  '23505', NULL, 'the same user cannot store an exercise externalRef twice'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000002', 'Theirs', 'strength', 'machines-atlas', 'ex-1') $$,
  'another user may hold the same exercise externalRef'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Other provider', 'strength', 'app', 'ex-1') $$,
  'the same external id from another provider is a different item'
);
-- Catalogue exercises (user_id NULL) are curated and never carry an externalRef.
INSERT INTO public.exercises (id, name, type) VALUES
  ('c1000000-0000-0000-0000-000000000001', 'Catalogue Press', 'strength');
SELECT throws_ok(
  $$ INSERT INTO public.exercises (name, type, external_provider, external_id)
     VALUES ('Catalogue', 'strength', 'machines-atlas', 'cat-1') $$,
  '23514', 'new row for relation "exercises" violates check constraint "exercises_catalogue_has_no_external_ref"',
  'a catalogue exercise cannot carry an externalRef'
);
SELECT throws_ok(
  $$ UPDATE public.exercises SET external_provider = 'machines-atlas', external_id = 'cat-1'
     WHERE id = 'c1000000-0000-0000-0000-000000000001' $$,
  '23514', 'new row for relation "exercises" violates check constraint "exercises_catalogue_has_no_external_ref"',
  'a catalogue exercise cannot gain an externalRef later'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (name, type, external_provider) VALUES ('Half catalogue', 'strength', 'machines-atlas') $$,
  '23514', NULL, 'a catalogue exercise cannot carry only an external provider'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (name, type, external_id) VALUES ('Half catalogue', 'strength', 'cat-2') $$,
  '23514', NULL, 'a catalogue exercise cannot carry only an external id'
);
SELECT throws_ok(
  $$ UPDATE public.exercises SET user_id = NULL
     WHERE user_id = '00000000-0000-0000-0000-000000000001' AND external_provider = 'machines-atlas' AND external_id = 'ex-1' $$,
  '23514', 'new row for relation "exercises" violates check constraint "exercises_catalogue_has_no_external_ref"',
  'an imported exercise cannot be moved into the catalogue'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Half ref', 'strength', 'machines-atlas') $$,
  '23514', NULL, 'externalRef needs both provider and id'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad slug', 'strength', 'Machines Atlas', 'x') $$,
  '23514', NULL, 'provider must be a lower-case slug'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Empty id', 'strength', 'machines-atlas', '') $$,
  '23514', NULL, 'external id cannot be empty'
);
SELECT lives_ok(
  $$ INSERT INTO public.routines (user_id, name, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Imported routine', 'machines-atlas', 'r-1') $$,
  'an imported routine stores its externalRef'
);
SELECT throws_ok(
  $$ INSERT INTO public.routines (user_id, name, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Again', 'machines-atlas', 'r-1') $$,
  '23505', NULL, 'routine externalRef is unique per user'
);
SELECT lives_ok(
  $$ INSERT INTO public.sessions (user_id, completed_at, time_zone, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', now(), 'UTC', 'machines-atlas', '2030-03-04') $$,
  'an imported session stores its externalRef'
);
SELECT throws_ok(
  $$ INSERT INTO public.sessions (user_id, completed_at, time_zone, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', now(), 'UTC', 'machines-atlas', '2030-03-04') $$,
  '23505', NULL, 'session externalRef is unique per user'
);
SELECT lives_ok(
  $$ UPDATE public.entries SET external_provider = 'machines-atlas', external_id = '5001'
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  'a merged entry gains the imported entry externalRef'
);
SELECT throws_ok(
  $$ UPDATE public.entries SET external_provider = 'machines-atlas', external_id = '5001'
     WHERE id = 'e1000000-0000-0000-0000-000000000002' $$,
  '23505', NULL, 'entry externalRef is unique per user'
);
SELECT lives_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, weight, weight_unit, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 1, 'imported',
             10, 40, 'kg', 'machines-atlas', '5001#1') $$,
  'an imported set stores its externalRef'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, weight, weight_unit, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 2, 'imported',
             10, 40, 'kg', 'machines-atlas', '5001#1') $$,
  '23505', NULL, 'set externalRef is unique per user'
);
SELECT lives_ok(
  $$ INSERT INTO public.sessions (user_id, completed_at, time_zone) VALUES
       ('00000000-0000-0000-0000-000000000001', now(), 'UTC'),
       ('00000000-0000-0000-0000-000000000001', now(), 'UTC') $$,
  'rows without externalRef never collide'
);

-- ---------------------------------------------------------------
-- importedNeedsExternalRef
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 5, 'imported', 10) $$,
  '23514', NULL, 'an imported set needs an externalRef'
);
SELECT lives_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, weight, weight_unit)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 1, 'manual', 10, 40, 'kg') $$,
  'a manual set needs no externalRef'
);
SELECT is(
  (SELECT superseded FROM public.sets WHERE entry_id = 'e1000000-0000-0000-0000-000000000001' AND source = 'manual'),
  false,
  'superseded defaults to false'
);

-- ---------------------------------------------------------------
-- order: unique positions per parent (and per source for sets)
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 1, 'manual', 9) $$,
  '23505', NULL, 'two manual sets cannot share a position in an entry'
);
SELECT lives_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 2, 'manual', 9) $$,
  'a manual set can take position 2 while an imported set holds position 1'
);
SELECT lives_ok(
  $$ UPDATE public.sets SET position = 3 - position
     WHERE entry_id = 'e1000000-0000-0000-0000-000000000001' AND source = 'manual' $$,
  'set positions can be swapped in one statement'
);
SELECT throws_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 1,
             'a1000000-0000-0000-0000-000000000003', 'skipped') $$,
  '23505', NULL, 'two entries cannot share a position in a session'
);
SELECT lives_ok(
  $$ UPDATE public.entries SET position = 3 - position
     WHERE session_id = 'd1000000-0000-0000-0000-000000000001' AND position IN (1, 2) $$,
  'entry positions can be swapped in one statement'
);
SELECT lives_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 1,
             'a1000000-0000-0000-0000-000000000001') $$,
  'a routine item takes position 1'
);
SELECT throws_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 1,
             'a1000000-0000-0000-0000-000000000002') $$,
  '23505', NULL, 'two routine items cannot share a position'
);
SELECT throws_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 0,
             'a1000000-0000-0000-0000-000000000002') $$,
  '23514', NULL, 'positions start at 1'
);

-- ---------------------------------------------------------------
-- one-entry-per-exercise
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 4,
             'a1000000-0000-0000-0000-000000000001', 'done') $$,
  '23505', NULL, 'a session has at most one done entry per exercise'
);
SELECT lives_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 4,
             'a1000000-0000-0000-0000-000000000001', 'removed') $$,
  'a removed entry may repeat a done exercise'
);
SELECT lives_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status)
     VALUES ('00000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000002', 1,
             'a1000000-0000-0000-0000-000000000001', 'done') $$,
  'the same exercise can be done in another session'
);

-- ---------------------------------------------------------------
-- reconciliation
-- ---------------------------------------------------------------
SELECT lives_ok(
  $$ UPDATE public.entries SET reconciliation_keep = 'imported', reconciliation_decided_by = 'default',
       reconciliation_decided_at = now()
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  'the default decision keeps the imported sets'
);
SELECT throws_ok(
  $$ UPDATE public.entries SET reconciliation_keep = 'manual', reconciliation_decided_by = 'default'
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'a default decision cannot keep the manual sets'
);
SELECT lives_ok(
  $$ UPDATE public.entries SET reconciliation_keep = 'manual', reconciliation_decided_by = 'user'
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  'the user can keep the manual sets'
);
SELECT throws_ok(
  $$ UPDATE public.entries SET reconciliation_keep = 'manual', reconciliation_decided_by = NULL
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'keep needs decidedBy'
);
SELECT throws_ok(
  $$ UPDATE public.entries SET reconciliation_keep = NULL, reconciliation_decided_by = NULL,
       reconciliation_decided_at = now()
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'decidedAt needs a decision'
);

-- ---------------------------------------------------------------
-- set fields (schema anyOf, dependentRequired, ranges)
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 9, 'manual') $$,
  '23514', NULL, 'a set needs reps or a duration'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, weight)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 9, 'manual', 5, 20) $$,
  '23514', NULL, 'a weight always states its unit'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, rir)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 9, 'manual', 5, 11) $$,
  '23514', NULL, 'rir is at most 10'
);
SELECT lives_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, weight, weight_unit, duration_seconds)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 9, 'manual', 5, 0, 'kg', 40) $$,
  'a strength set may carry zero weight and time under load'
);

-- ---------------------------------------------------------------
-- exercise-type: cardio sets
-- ---------------------------------------------------------------
SELECT lives_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, duration_seconds, distance_meters)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 1, 'manual', 600, 2000) $$,
  'a cardio set has a duration and a distance'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, duration_seconds)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 2, 'manual', 10, 60) $$,
  '23514', NULL, 'a cardio set has no reps'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, duration_seconds, weight, weight_unit)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 2, 'manual', 60, 5, 'kg') $$,
  '23514', NULL, 'a cardio set has no weight'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, distance_meters)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000002', 2, 'manual', 100) $$,
  '23514', NULL, 'distance requires a duration'
);
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, duration_seconds, distance_meters)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 10, 'manual', 5, 60, 100) $$,
  '23514', NULL, 'only cardio sets have a distance'
);
SELECT throws_ok(
  $$ UPDATE public.sets SET reps = 3 WHERE entry_id = 'e1000000-0000-0000-0000-000000000002' $$,
  '23514', NULL, 'the cardio rule also holds on update'
);

-- ---------------------------------------------------------------
-- entry status: skipped entries have no sets
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, duration_seconds)
     VALUES ('00000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000003', 1, 'manual', 30) $$,
  '23514', NULL, 'a skipped entry has no sets'
);
SELECT throws_ok(
  $$ UPDATE public.entries SET status = 'skipped' WHERE id = 'e1000000-0000-0000-0000-000000000002' $$,
  '23514', NULL, 'an entry with sets cannot become skipped'
);
SELECT lives_ok(
  $$ UPDATE public.entries SET status = 'removed' WHERE id = 'e1000000-0000-0000-0000-000000000002' $$,
  'an entry with sets can be removed; its sets stay stored'
);

-- ---------------------------------------------------------------
-- range: session times and entry completion
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.sessions (user_id, started_at, completed_at, time_zone)
     VALUES ('00000000-0000-0000-0000-000000000001', '2030-03-04T19:00:00Z', '2030-03-04T18:00:00Z', 'UTC') $$,
  '23514', NULL, 'startedAt cannot be after completedAt'
);
SELECT throws_ok(
  $$ INSERT INTO public.sessions (user_id, started_at, completed_at, time_zone, duration_seconds)
     VALUES ('00000000-0000-0000-0000-000000000001', '2030-03-04T17:00:00Z', '2030-03-04T18:00:00Z', 'UTC', 3601) $$,
  '23514', NULL, 'the duration fits between start and end'
);
SELECT lives_ok(
  $$ INSERT INTO public.sessions (user_id, completed_at, time_zone, duration_seconds)
     VALUES ('00000000-0000-0000-0000-000000000001', '2030-03-04T18:00:00Z', 'UTC', 3000) $$,
  'an imported session without startedAt may state a duration'
);
SELECT throws_ok(
  $$ INSERT INTO public.sessions (user_id, completed_at, time_zone)
     VALUES ('00000000-0000-0000-0000-000000000001', now(), 'Madrid time') $$,
  '23514', NULL, 'timeZone must look like an IANA zone'
);
SELECT throws_ok(
  $$ UPDATE public.entries SET completed_at = '2030-03-04T18:30:00Z' WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'no entry is completed after its session'
);
SELECT lives_ok(
  $$ UPDATE public.entries SET completed_at = '2030-03-04T17:30:00Z' WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  'an entry completed inside its session is accepted'
);
SELECT throws_ok(
  $$ UPDATE public.sessions SET completed_at = '2030-03-04T17:20:00Z' WHERE id = 'd1000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'a session cannot end before one of its entries'
);

-- ---------------------------------------------------------------
-- routine targets and exercise details
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.routine_items (user_id, routine_id, position, exercise_id, target_reps_min, target_reps_max)
     VALUES ('00000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 5,
             'a1000000-0000-0000-0000-000000000001', 12, 8) $$,
  '23514', NULL, 'targetReps min cannot exceed max'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, setup_steps)
     VALUES ('00000000-0000-0000-0000-000000000001', 'No steps', 'strength', '{}') $$,
  '23514', NULL, 'an instruction list has at least one step'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'With videos', 'strength',
             '[{"title":"Setup","url":"https://video.example/a","source":"Example"}, {"title":"Range","url":"https://video.example/b","source":"Example"}]') $$,
  'an exercise lists related videos with a title, an https url and a source'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad videos', 'strength', '{"title":"Setup","url":"https://video.example/a","source":"Example"}') $$,
  '23514', NULL, 'related videos are a list, not an object'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad videos', 'strength', '[]') $$,
  '23514', NULL, 'the list of related videos is never empty'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad videos', 'strength', '[{"title":"Setup","url":"http://video.example/a","source":"Example"}]') $$,
  '23514', NULL, 'a related video url is https'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad videos', 'strength', '[{"title":"","url":"https://video.example/a","source":"Example"}]') $$,
  '23514', NULL, 'a related video has a title'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad videos', 'strength', '[{"title":"Setup","url":"https://video.example/a"}]') $$,
  '23514', NULL, 'a related video has a source'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad videos', 'strength', '[{"title":"Setup","url":"https://video.example/a","source":"Example","extra":1}]') $$,
  '23514', NULL, 'a related video has no other fields'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, related_videos)
     VALUES ('00000000-0000-0000-0000-000000000001', 'Bad videos', 'strength', '["https://video.example/a"]') $$,
  '23514', NULL, 'every related video is an object'
);
SELECT lives_ok(
  $$ INSERT INTO public.exercise_muscle_groups (exercise_id, muscle, role)
     VALUES ('a1000000-0000-0000-0000-000000000001', 'chest', 'primary') $$,
  'an exercise lists a muscle group'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_muscle_groups (exercise_id, muscle, role)
     VALUES ('a1000000-0000-0000-0000-000000000001', 'chest', 'primary') $$,
  '23505', NULL, 'a muscle group appears once per role'
);

-- ---------------------------------------------------------------
-- exercise_settings: rest between sets per user and exercise (L15)
-- ---------------------------------------------------------------
INSERT INTO public.exercises (id, user_id, name, type) VALUES
  ('a1000000-0000-0000-0000-000000000090', '00000000-0000-0000-0000-000000000001', 'Settings Curl', 'strength');
SELECT results_eq(
  $$ INSERT INTO public.exercise_settings (user_id, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000090')
     RETURNING rest_enabled, rest_seconds $$,
  $$ VALUES (true, 90) $$,
  'a new rest setting is enabled with 90 seconds by default'
);
SELECT results_eq(
  $$ INSERT INTO public.exercise_settings (user_id, exercise_id, rest_enabled, rest_seconds)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000090', false, 120)
     ON CONFLICT (user_id, exercise_id)
     DO UPDATE SET rest_enabled = EXCLUDED.rest_enabled, rest_seconds = EXCLUDED.rest_seconds
     RETURNING rest_enabled, rest_seconds $$,
  $$ VALUES (false, 120) $$,
  'saving a rest setting again updates it (upsert on user_id, exercise_id)'
);
SELECT is(
  (SELECT count(*)::int FROM public.exercise_settings WHERE exercise_id = 'a1000000-0000-0000-0000-000000000090'),
  1, 'one rest setting per user and exercise'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_settings (user_id, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000090') $$,
  '23505', NULL, 'a second rest setting for the same user and exercise is a duplicate'
);
SELECT lives_ok(
  $$ UPDATE public.exercise_settings SET rest_seconds = 0 WHERE exercise_id = 'a1000000-0000-0000-0000-000000000090' $$,
  'rest_seconds accepts 0'
);
SELECT lives_ok(
  $$ UPDATE public.exercise_settings SET rest_seconds = 3600 WHERE exercise_id = 'a1000000-0000-0000-0000-000000000090' $$,
  'rest_seconds accepts 3600'
);
SELECT throws_ok(
  $$ UPDATE public.exercise_settings SET rest_seconds = -1 WHERE exercise_id = 'a1000000-0000-0000-0000-000000000090' $$,
  '23514', NULL, 'rest_seconds is never negative'
);
SELECT throws_ok(
  $$ UPDATE public.exercise_settings SET rest_seconds = 3601 WHERE exercise_id = 'a1000000-0000-0000-0000-000000000090' $$,
  '23514', NULL, 'rest_seconds is at most 3600'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercise_settings (user_id, exercise_id)
     VALUES ('00000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-0000000000ff') $$,
  '23503', NULL, 'a rest setting needs an existing exercise'
);
SELECT lives_ok(
  $$ DELETE FROM public.exercises WHERE id = 'a1000000-0000-0000-0000-000000000090' $$,
  'an exercise with rest settings can be deleted'
);
SELECT is(
  (SELECT count(*)::int FROM public.exercise_settings WHERE exercise_id = 'a1000000-0000-0000-0000-000000000090'),
  0, 'deleting an exercise deletes its rest settings'
);

-- ---------------------------------------------------------------
-- Receiver-owned keys (decision B): same externalRef, two users, two rows
-- ---------------------------------------------------------------
INSERT INTO public.sessions (id, user_id, completed_at, time_zone, external_provider, external_id) VALUES
  ('d2000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', '2030-03-04T18:00:00Z', 'UTC',
   'machines-atlas', '2030-03-04');
SELECT is(
  (SELECT count(DISTINCT id)::int FROM public.sessions WHERE external_provider = 'machines-atlas' AND external_id = '2030-03-04'),
  2, 'two users import the same provider session as two rows'
);
SELECT lives_ok(
  $$ INSERT INTO public.entries (user_id, session_id, position, exercise_id, status, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000001', 1,
             'c1000000-0000-0000-0000-000000000001', 'done',
             'machines-atlas', '5001') $$,
  'another user imports the same provider entry'
);
SELECT lives_ok(
  $$ INSERT INTO public.sets (user_id, entry_id, position, source, reps, external_provider, external_id)
     SELECT '00000000-0000-0000-0000-000000000002', id, 1, 'imported', 8, 'machines-atlas', '5001#1'
       FROM public.entries WHERE user_id = '00000000-0000-0000-0000-000000000002' AND external_id = '5001' $$,
  'another user imports the same provider set'
);
SELECT is(
  (SELECT count(DISTINCT id)::int FROM public.sets WHERE external_provider = 'machines-atlas' AND external_id = '5001#1'),
  2, 'the same provider set is two rows with different keys'
);

-- ---------------------------------------------------------------
-- exercise-type when an entry changes exercise
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ UPDATE public.entries SET exercise_id = 'a1000000-0000-0000-0000-000000000002'
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'an entry with strength sets cannot switch to a cardio exercise'
);
SELECT lives_ok(
  $$ UPDATE public.entries SET exercise_id = 'a1000000-0000-0000-0000-000000000003'
     WHERE id = 'e1000000-0000-0000-0000-000000000001' $$,
  'an entry can switch to an exercise its sets fit'
);
SELECT throws_ok(
  $$ UPDATE public.entries SET exercise_id = 'a1000000-0000-0000-0000-000000000001'
     WHERE id = 'e1000000-0000-0000-0000-000000000002' $$,
  '23514', NULL, 'an entry with distance sets cannot switch to a non-cardio exercise'
);

-- ---------------------------------------------------------------
-- Input bounds
-- ---------------------------------------------------------------
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type) VALUES ('00000000-0000-0000-0000-000000000001', '   ', 'strength') $$,
  '23514', NULL, 'an exercise name cannot be blank'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type) VALUES ('00000000-0000-0000-0000-000000000001', repeat('x', 201), 'strength') $$,
  '23514', NULL, 'an exercise name has at most 200 characters'
);
SELECT throws_ok(
  $$ INSERT INTO public.exercises (user_id, name, type, external_provider, external_id) VALUES ('00000000-0000-0000-0000-000000000001', 'Long ref', 'strength', 'machines-atlas', repeat('9', 201)) $$,
  '23514', NULL, 'an external id has at most 200 characters'
);
SELECT throws_ok(
  $$ INSERT INTO public.sessions (user_id, completed_at, time_zone, external_provider, external_id)
     VALUES ('00000000-0000-0000-0000-000000000001', now(), 'UTC', 'machines-atlas', repeat('9', 201)) $$,
  '23514', NULL, 'the external id cap applies to every table'
);

-- Deleting a routine keeps the sessions started from it
SELECT lives_ok(
  $$ INSERT INTO public.sessions (id, user_id, routine_id, completed_at, time_zone)
     VALUES ('d1000000-0000-0000-0000-000000000009', '00000000-0000-0000-0000-000000000001',
             'b1000000-0000-0000-0000-000000000001', now(), 'UTC') $$,
  'a session started from a routine'
);
SELECT lives_ok(
  $$ DELETE FROM public.routines WHERE id = 'b1000000-0000-0000-0000-000000000001' $$,
  'a routine that sessions were started from can be deleted'
);
SELECT is(
  (SELECT routine_id FROM public.sessions WHERE id = 'd1000000-0000-0000-0000-000000000009'),
  NULL::uuid,
  'the session stays and loses only its routine_id'
);

SELECT * FROM finish();
ROLLBACK;
