-- Migration: drop the legacy workout schema (issue #133).
--
-- The tables below are replaced by the training-data schema in the next
-- migration (docs/training-data-format.md). Kept: public.users (profile and
-- preferences), its auth trigger, tg_set_updated_at, and the weight_unit and
-- timer_trigger_mode types, which the app still uses.
--
-- DESTRUCTIVE: before pushing this to a hosted project, check that it holds
-- no data worth keeping (docs/deploy.md, "Destructive migrations").
--
-- Objects are dropped explicitly in dependency order, without CASCADE, so an
-- unexpected dependency stops the migration instead of silently removing it.

-- Functions over the old tables
DROP FUNCTION IF EXISTS public.refresh_mv_weekly_volume();
DROP FUNCTION IF EXISTS public.get_exercise_alternatives(uuid, uuid, integer);
DROP FUNCTION IF EXISTS public.clone_plan(uuid, text);
DROP FUNCTION IF EXISTS public.clone_routine(uuid, text);
DROP FUNCTION IF EXISTS public.clone_session(uuid, text);
DROP FUNCTION IF EXISTS public.reorder_items(text, text, uuid, jsonb);

-- Materialized view over workouts
DROP MATERIALIZED VIEW IF EXISTS public.mv_user_weekly_volume;

-- Execution tables (leaves first)
DROP TABLE IF EXISTS public.personal_records;
DROP TABLE IF EXISTS public.rest_timers;
DROP TABLE IF EXISTS public.exercise_sets;
DROP TABLE IF EXISTS public.workout_exercises;
DROP TABLE IF EXISTS public.workouts;

-- Template tables
DROP TABLE IF EXISTS public.session_exercises;
DROP TABLE IF EXISTS public.routine_sessions;
DROP TABLE IF EXISTS public.plan_routines;
DROP TABLE IF EXISTS public.sessions;
DROP TABLE IF EXISTS public.routines;
DROP TABLE IF EXISTS public.plans;

-- Catalogue and unused content
DROP TABLE IF EXISTS public.exercise_videos;
DROP TABLE IF EXISTS public.exercises;
DROP TABLE IF EXISTS public.motivational_quotes;

-- Trigger function of the dropped exercise_sets table
DROP FUNCTION IF EXISTS public.tg_immutable_completed_at();

-- Types only the old tables used. The running rest timer now lives on the
-- device, so timer_type is not recreated.
DROP TYPE IF EXISTS public.exercise_category;
DROP TYPE IF EXISTS public.video_source;
DROP TYPE IF EXISTS public.workout_status;
DROP TYPE IF EXISTS public.workout_exercise_status;
DROP TYPE IF EXISTS public.pr_record_type;
DROP TYPE IF EXISTS public.timer_type;

-- Extensions only the old trigram and GIN indexes used
DROP EXTENSION IF EXISTS btree_gin;
DROP EXTENSION IF EXISTS pg_trgm;
