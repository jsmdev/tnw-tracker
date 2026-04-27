-- Migration: Execution tables — workouts, workout_exercises, exercise_sets, rest_timers, personal_records, motivational_quotes

CREATE TABLE IF NOT EXISTS public.workouts (
  id               UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          UUID            NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  session_id       UUID            REFERENCES public.sessions(id) ON DELETE SET NULL,
  name             TEXT            NOT NULL,
  status           workout_status  NOT NULL DEFAULT 'active',
  started_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
  completed_at     TIMESTAMPTZ,
  duration_seconds INT,
  notes            TEXT,
  created_at       TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- Only one active or paused workout per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_workouts_one_active_per_user
  ON public.workouts (user_id)
  WHERE status IN ('active', 'paused');

CREATE TABLE IF NOT EXISTS public.workout_exercises (
  id                  UUID                    PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_id          UUID                    NOT NULL REFERENCES public.workouts(id) ON DELETE CASCADE,
  exercise_id         UUID                    NOT NULL REFERENCES public.exercises(id) ON DELETE RESTRICT,
  session_exercise_id UUID                    REFERENCES public.session_exercises(id) ON DELETE SET NULL,
  order_index         INT                     NOT NULL,
  status              workout_exercise_status NOT NULL DEFAULT 'pending',
  notes               TEXT,
  created_at          TIMESTAMPTZ             NOT NULL DEFAULT now(),
  UNIQUE (workout_id, order_index)
);

CREATE TABLE IF NOT EXISTS public.exercise_sets (
  id                   UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_exercise_id  UUID         NOT NULL REFERENCES public.workout_exercises(id) ON DELETE CASCADE,
  set_number           INT          NOT NULL,
  reps                 INT,
  weight               DECIMAL(8,2),
  weight_unit          weight_unit  NOT NULL DEFAULT 'kg',
  rpe                  INT          CHECK (rpe >= 1 AND rpe <= 10),
  is_warmup            BOOLEAN      NOT NULL DEFAULT false,
  is_personal_record   BOOLEAN      NOT NULL DEFAULT false,
  completed_at         TIMESTAMPTZ,
  notes                TEXT,
  created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (workout_exercise_id, set_number)
);

CREATE TABLE IF NOT EXISTS public.rest_timers (
  id               UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  workout_id       UUID        NOT NULL REFERENCES public.workouts(id) ON DELETE CASCADE,
  timer_type       timer_type  NOT NULL,
  duration_seconds INT         NOT NULL,
  started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at          TIMESTAMPTZ NOT NULL,
  is_active        BOOLEAN     NOT NULL DEFAULT true,
  exercise_id      UUID        REFERENCES public.exercises(id) ON DELETE SET NULL,
  set_number       INT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Only one active timer per workout
CREATE UNIQUE INDEX IF NOT EXISTS idx_rest_timers_one_active_per_workout
  ON public.rest_timers (workout_id)
  WHERE is_active = true;

CREATE TABLE IF NOT EXISTS public.personal_records (
  id             UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID            NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  exercise_id    UUID            NOT NULL REFERENCES public.exercises(id) ON DELETE CASCADE,
  exercise_set_id UUID           REFERENCES public.exercise_sets(id) ON DELETE SET NULL,
  record_type    pr_record_type  NOT NULL,
  value          DECIMAL(10,3)   NOT NULL,
  weight_unit    weight_unit     NOT NULL DEFAULT 'kg',
  achieved_at    TIMESTAMPTZ     NOT NULL,
  created_at     TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.motivational_quotes (
  id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  content    TEXT        NOT NULL,
  author     TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
