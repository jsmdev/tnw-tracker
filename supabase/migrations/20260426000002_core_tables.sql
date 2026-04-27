-- Migration: Core tables — users, exercises, exercise_videos

CREATE TABLE IF NOT EXISTS public.users (
  id                  UUID          PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email               TEXT          NOT NULL,
  weight_unit         weight_unit   NOT NULL DEFAULT 'kg',
  timer_trigger_mode  timer_trigger_mode NOT NULL DEFAULT 'auto',
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.exercises (
  id             UUID               PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID               REFERENCES public.users(id) ON DELETE CASCADE,  -- NULL = global
  name           TEXT               NOT NULL,
  category       exercise_category  NOT NULL,
  muscle_groups  TEXT[]             NOT NULL DEFAULT '{}',
  instructions   TEXT,
  is_active      BOOLEAN            NOT NULL DEFAULT true,
  is_public      BOOLEAN            NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ        NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ        NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.exercise_videos (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  exercise_id     UUID          NOT NULL REFERENCES public.exercises(id) ON DELETE CASCADE,
  source          video_source  NOT NULL,
  url             TEXT          NOT NULL,
  order_index     INT           NOT NULL DEFAULT 0,
  is_downloadable BOOLEAN       NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);
