-- Migration: ENUMs and extensions
-- Idempotent via DO blocks

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- weight_unit
DO $$ BEGIN
  CREATE TYPE public.weight_unit AS ENUM ('kg', 'lb');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- exercise_category
DO $$ BEGIN
  CREATE TYPE public.exercise_category AS ENUM ('Push', 'Pull', 'Legs', 'Core', 'Cardio', 'Other');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- video_source
DO $$ BEGIN
  CREATE TYPE public.video_source AS ENUM ('youtube', 'storage');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- workout_status
DO $$ BEGIN
  CREATE TYPE public.workout_status AS ENUM ('active', 'paused', 'completed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- workout_exercise_status
DO $$ BEGIN
  CREATE TYPE public.workout_exercise_status AS ENUM ('pending', 'in_progress', 'completed', 'skipped');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- timer_type
DO $$ BEGIN
  CREATE TYPE public.timer_type AS ENUM ('between_sets', 'between_exercises');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- pr_record_type
DO $$ BEGIN
  CREATE TYPE public.pr_record_type AS ENUM ('max_weight', 'max_reps', 'max_volume');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- timer_trigger_mode
DO $$ BEGIN
  CREATE TYPE public.timer_trigger_mode AS ENUM ('auto', 'manual');
EXCEPTION WHEN duplicate_object THEN null;
END $$;
