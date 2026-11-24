-- pgTAP: shape of the training-data schema (issue #133).
-- Old objects are gone, new objects exist, every public table has RLS,
-- and the API roles have exactly the privileges they need.
BEGIN;

SELECT plan(80);

-- ---------------------------------------------------------------
-- Old schema removed (S5)
-- ---------------------------------------------------------------
SELECT hasnt_table('public', 'workouts', 'workouts dropped');
SELECT hasnt_table('public', 'workout_exercises', 'workout_exercises dropped');
SELECT hasnt_table('public', 'exercise_sets', 'exercise_sets dropped');
SELECT hasnt_table('public', 'personal_records', 'personal_records dropped');
SELECT hasnt_table('public', 'plans', 'plans dropped');
SELECT hasnt_table('public', 'plan_routines', 'plan_routines dropped');
SELECT hasnt_table('public', 'routine_sessions', 'routine_sessions dropped');
SELECT hasnt_table('public', 'session_exercises', 'session_exercises dropped');
SELECT hasnt_table('public', 'exercise_videos', 'exercise_videos dropped');
SELECT hasnt_table('public', 'motivational_quotes', 'motivational_quotes dropped');
SELECT hasnt_materialized_view('public', 'mv_user_weekly_volume', 'weekly volume view dropped');

SELECT hasnt_function('public', 'get_exercise_alternatives', 'get_exercise_alternatives dropped');
SELECT hasnt_function('public', 'clone_plan', 'clone_plan dropped');
SELECT hasnt_function('public', 'clone_routine', 'clone_routine dropped');
SELECT hasnt_function('public', 'clone_session', 'clone_session dropped');
SELECT hasnt_function('public', 'reorder_items', 'reorder_items dropped');
SELECT hasnt_function('public', 'refresh_mv_weekly_volume', 'refresh_mv_weekly_volume dropped');
SELECT hasnt_function('public', 'tg_immutable_completed_at', 'tg_immutable_completed_at dropped');

SELECT hasnt_type('public', 'exercise_category', 'exercise_category dropped');
SELECT hasnt_type('public', 'video_source', 'video_source dropped');
SELECT hasnt_type('public', 'workout_status', 'workout_status dropped');
SELECT hasnt_type('public', 'workout_exercise_status', 'workout_exercise_status dropped');
SELECT hasnt_type('public', 'pr_record_type', 'pr_record_type dropped');

-- ---------------------------------------------------------------
-- New schema present (S1)
-- ---------------------------------------------------------------
SELECT tables_are(
  'public',
  ARRAY[
    'users', 'exercises', 'exercise_muscle_groups', 'routines', 'routine_items',
    'sessions', 'entries', 'sets', 'exercise_settings', 'tombstones'
  ],
  'public holds exactly the new tables'
);

SELECT enum_has_labels('public', 'exercise_type', ARRAY['strength', 'bodyweight', 'cardio'], 'exercise_type labels');
SELECT enum_has_labels(
  'public', 'equipment',
  ARRAY['none', 'free_weights', 'machine', 'connected_machine', 'cardio_machine', 'other'],
  'equipment labels'
);
SELECT enum_has_labels(
  'public', 'muscle_group',
  ARRAY['chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms', 'core',
        'glutes', 'quadriceps', 'hamstrings', 'calves', 'hips', 'neck'],
  'muscle_group labels (O14: thirteen groups)'
);
SELECT enum_has_labels('public', 'muscle_role', ARRAY['primary', 'secondary'], 'muscle_role labels');
SELECT enum_has_labels('public', 'entry_status', ARRAY['done', 'skipped', 'removed'], 'entry_status labels');
SELECT enum_has_labels('public', 'set_source', ARRAY['manual', 'imported'], 'set_source labels');
SELECT enum_has_labels('public', 'reconciliation_decider', ARRAY['default', 'user'], 'reconciliation_decider labels');
SELECT enum_has_labels('public', 'weight_unit', ARRAY['kg', 'lb'], 'weight_unit labels');
SELECT enum_has_labels('public', 'timer_trigger_mode', ARRAY['auto', 'manual'], 'timer_trigger_mode labels');

-- No remote rest timer (L17): the running timer lives on the device.
SELECT hasnt_table('public', 'rest_timers', 'rest_timers dropped');
SELECT hasnt_type('public', 'timer_type', 'timer_type dropped');
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'rest_timers'
  ),
  'rest_timers is not published to supabase_realtime'
);

-- ---------------------------------------------------------------
-- RLS on every public table (S2)
-- ---------------------------------------------------------------
SELECT is_empty(
  $$
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
  $$,
  'every public table has RLS enabled'
);

-- ---------------------------------------------------------------
-- API role privileges (PR #100 superseded by explicit grants)
-- ---------------------------------------------------------------
SELECT is_empty(
  $$
    SELECT t FROM unnest(ARRAY[
      'users', 'exercises', 'exercise_muscle_groups', 'routines', 'routine_items',
      'sessions', 'entries', 'sets', 'exercise_settings'
    ]) AS t
    WHERE has_table_privilege('anon', 'public.' || t, 'SELECT')
       OR has_table_privilege('anon', 'public.' || t, 'INSERT')
       OR has_table_privilege('anon', 'public.' || t, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || t, 'DELETE')
  $$,
  'anon has no DML on any table'
);

SELECT is_empty(
  $$
    SELECT t FROM unnest(ARRAY[
      'users', 'exercises', 'exercise_muscle_groups', 'routines', 'routine_items',
      'sessions', 'entries', 'sets', 'exercise_settings'
    ]) AS t
    WHERE NOT (
      has_table_privilege('authenticated', 'public.' || t, 'SELECT')
      AND has_table_privilege('authenticated', 'public.' || t, 'INSERT')
      AND has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
      AND has_table_privilege('authenticated', 'public.' || t, 'DELETE')
    )
  $$,
  'authenticated has DML on every table (RLS restricts rows)'
);

SELECT is_empty(
  $$
    SELECT t FROM unnest(ARRAY[
      'users', 'exercises', 'exercise_muscle_groups', 'routines', 'routine_items',
      'sessions', 'entries', 'sets', 'exercise_settings'
    ]) AS t
    WHERE NOT (
      has_table_privilege('service_role', 'public.' || t, 'SELECT')
      AND has_table_privilege('service_role', 'public.' || t, 'INSERT')
      AND has_table_privilege('service_role', 'public.' || t, 'UPDATE')
      AND has_table_privilege('service_role', 'public.' || t, 'DELETE')
    )
  $$,
  'service_role has DML on every table'
);

SELECT ok(
  has_schema_privilege('authenticated', 'public', 'USAGE')
  AND has_schema_privilege('service_role', 'public', 'USAGE'),
  'authenticated and service_role can use schema public'
);
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.exercises', 'TRUNCATE'),
  'authenticated cannot TRUNCATE'
);

-- Trigger functions are not callable through the API
SELECT is_empty(
  $$
    SELECT p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prorettype = 'trigger'::regtype
      AND (has_function_privilege('anon', p.oid, 'EXECUTE')
           OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  $$,
  'API roles cannot execute public trigger functions'
);

-- The catalogue is curated: no function writes it, and it never holds an externalRef.
SELECT hasnt_function('public', 'ensure_shared_exercise', 'no function adds shared catalogue exercises');
SELECT hasnt_index('public', 'exercises', 'exercises_catalog_external_ref_key', 'the catalogue has no externalRef index');
SELECT ok(
  EXISTS (SELECT 1 FROM pg_constraint
           WHERE conrelid = 'public.exercises'::regclass
             AND conname = 'exercises_catalogue_has_no_external_ref'
             AND contype = 'c'),
  'exercises_catalogue_has_no_external_ref exists'
);

-- ---------------------------------------------------------------
-- Column shape spot checks
-- ---------------------------------------------------------------
SELECT col_not_null('public', 'sessions', 'completed_at', 'sessions.completed_at is required');
SELECT col_not_null('public', 'sessions', 'time_zone', 'sessions.time_zone is required');
SELECT col_is_null('public', 'sessions', 'started_at', 'sessions.started_at is optional');
SELECT col_not_null('public', 'sets', 'source', 'sets.source is required');
SELECT col_default_is('public', 'sets', 'superseded', 'false', 'sets.superseded defaults to false');
SELECT col_not_null('public', 'sets', 'superseded', 'sets.superseded is never null');
SELECT has_column('public', 'routines', 'is_favorite', 'routines.is_favorite exists');
SELECT col_type_is('public', 'routines', 'is_favorite', 'boolean', 'routines.is_favorite is a boolean');
SELECT col_default_is('public', 'routines', 'is_favorite', 'false', 'routines.is_favorite defaults to false');
SELECT col_not_null('public', 'routines', 'is_favorite', 'routines.is_favorite is never null');
SELECT has_column('public', 'sets', 'warmup', 'sets.warmup exists');
SELECT col_type_is('public', 'sets', 'warmup', 'boolean', 'sets.warmup is a boolean');
SELECT col_default_is('public', 'sets', 'warmup', 'false', 'sets.warmup defaults to false');
SELECT col_not_null('public', 'sets', 'warmup', 'sets.warmup is never null');
SELECT col_type_is('public', 'exercises', 'setup_steps', 'text[]', 'instruction steps are text arrays');
SELECT has_column('public', 'exercises', 'related_links', 'exercises.related_links exists (format 1.2)');
SELECT col_type_is('public', 'exercises', 'related_links', 'jsonb', 'exercises.related_links is jsonb');
SELECT hasnt_column('public', 'exercises', 'related_videos', 'format 1.2 renamed exercises.related_videos to related_links');
SELECT has_function('public', 'related_links_are_valid', ARRAY['jsonb'], 'related_links_are_valid(jsonb) checks exercises.related_links');
SELECT hasnt_function('public', 'related_videos_are_valid', ARRAY['jsonb'], 'the 1.1 checker is renamed, not left behind');
SELECT ok(EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'exercises_related_links_valid' AND conrelid = 'public.exercises'::regclass), 'exercises_related_links_valid checks exercises.related_links');

-- exercise_settings: per-user rest between sets (L15, AC7.1, AC7.2)
SELECT col_is_pk('public', 'exercise_settings', ARRAY['user_id', 'exercise_id'], 'exercise_settings key is (user_id, exercise_id)');
SELECT col_default_is('public', 'exercise_settings', 'user_id', 'auth.uid()', 'exercise_settings.user_id defaults to the caller');
SELECT fk_ok('public', 'exercise_settings', 'user_id', 'public', 'users', 'id', 'exercise_settings.user_id references users');
SELECT fk_ok('public', 'exercise_settings', 'exercise_id', 'public', 'exercises', 'id', 'exercise_settings.exercise_id references exercises');
SELECT col_type_is('public', 'exercise_settings', 'rest_enabled', 'boolean', 'exercise_settings.rest_enabled is a boolean');
SELECT col_not_null('public', 'exercise_settings', 'rest_enabled', 'exercise_settings.rest_enabled is never null');
SELECT col_default_is('public', 'exercise_settings', 'rest_enabled', 'true', 'exercise_settings.rest_enabled defaults to true');
SELECT col_type_is('public', 'exercise_settings', 'rest_seconds', 'integer', 'exercise_settings.rest_seconds is an integer');
SELECT col_not_null('public', 'exercise_settings', 'rest_seconds', 'exercise_settings.rest_seconds is never null');
SELECT col_default_is('public', 'exercise_settings', 'rest_seconds', '90', 'exercise_settings.rest_seconds defaults to 90');
SELECT col_not_null('public', 'exercise_settings', 'updated_at', 'exercise_settings.updated_at is never null');
SELECT has_trigger('public', 'exercise_settings', 'set_updated_at', 'exercise_settings bumps updated_at on update');
SELECT has_index('public', 'exercise_settings', 'exercise_settings_exercise_id_idx', 'exercise_settings.exercise_id is indexed for the cascade');

SELECT * FROM finish();
ROLLBACK;
