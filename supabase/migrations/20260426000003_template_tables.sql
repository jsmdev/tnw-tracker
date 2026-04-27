-- Migration: Template tables — plans, routines, plan_routines, sessions, routine_sessions, session_exercises

CREATE TABLE IF NOT EXISTS public.plans (
  id             UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID         REFERENCES public.users(id) ON DELETE CASCADE,
  name           TEXT         NOT NULL,
  description    TEXT,
  duration_weeks INT,
  is_active      BOOLEAN      NOT NULL DEFAULT true,
  is_public      BOOLEAN      NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.routines (
  id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID         REFERENCES public.users(id) ON DELETE CASCADE,
  name        TEXT         NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT true,
  is_public   BOOLEAN      NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.plan_routines (
  id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_id     UUID         NOT NULL REFERENCES public.plans(id) ON DELETE CASCADE,
  routine_id  UUID         NOT NULL REFERENCES public.routines(id) ON DELETE RESTRICT,
  order_index INT          NOT NULL,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (plan_id, order_index)
);

CREATE TABLE IF NOT EXISTS public.sessions (
  id                              UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                         UUID         REFERENCES public.users(id) ON DELETE CASCADE,
  name                            TEXT         NOT NULL,
  description                     TEXT,
  rest_between_exercises_seconds  INT          NOT NULL DEFAULT 60,
  is_public                       BOOLEAN      NOT NULL DEFAULT false,
  created_at                      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at                      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.routine_sessions (
  id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  routine_id  UUID         NOT NULL REFERENCES public.routines(id) ON DELETE CASCADE,
  session_id  UUID         NOT NULL REFERENCES public.sessions(id) ON DELETE RESTRICT,
  order_index INT          NOT NULL,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (routine_id, order_index)
);

CREATE TABLE IF NOT EXISTS public.session_exercises (
  id                        UUID           PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id                UUID           NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  exercise_id               UUID           NOT NULL REFERENCES public.exercises(id) ON DELETE RESTRICT,
  order_index               INT            NOT NULL,
  target_sets               INT,
  target_reps               INT,
  target_weight             DECIMAL(8,2),
  rest_between_sets_seconds INT            NOT NULL DEFAULT 90,
  notes                     TEXT,
  created_at                TIMESTAMPTZ    NOT NULL DEFAULT now(),
  UNIQUE (session_id, order_index)
);
