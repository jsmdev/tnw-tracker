-- Migration: training-data schema (issue #133).
--
-- Implements docs/training-data-format.md (format 1.0): exercises, routines,
-- sessions, entries and sets, with externalRef, set source, reconciliation and
-- superseded sets. docs/database-schema.md maps every format field to a column.
--
-- Keys: every primary key is a meaningless UUID owned by the database. Clients
-- may supply their own on insert (the app does); rows created server-side get
-- gen_random_uuid(). Bundle ids are never used as keys: imported rows are
-- matched by externalRef, UNIQUE (user_id, external_provider, external_id) per
-- table, which is the upsert key.
--
-- Ownership: every user-owned row carries user_id. Child rows reference their
-- parent through a composite (parent_id, user_id) foreign key, so a row can
-- never point at another user's parent even though FK checks bypass RLS.
-- Exercises with user_id IS NULL are the curated catalogue: readable by every
-- signed-in user and written only with the service role. Catalogue rows never
-- carry an externalRef; an exercise imported from a provider is always a
-- private row of the importing user.

-- ===============================================================
-- Types
-- ===============================================================
CREATE TYPE public.exercise_type AS ENUM ('strength', 'bodyweight', 'cardio');

CREATE TYPE public.equipment AS ENUM (
  'none', 'free_weights', 'machine', 'connected_machine', 'cardio_machine', 'other'
);

CREATE TYPE public.muscle_group AS ENUM (
  'chest', 'back', 'shoulders', 'biceps', 'triceps', 'forearms', 'core',
  'glutes', 'quadriceps', 'hamstrings', 'calves', 'hips', 'neck'
);

CREATE TYPE public.muscle_role AS ENUM ('primary', 'secondary');

CREATE TYPE public.entry_status AS ENUM ('done', 'skipped', 'removed');

-- Format "origin": manual = logged by hand in the app, imported = by an importer.
CREATE TYPE public.set_source AS ENUM ('manual', 'imported');

CREATE TYPE public.reconciliation_decider AS ENUM ('default', 'user');

-- Same cases as the app's Swift TimerType.
CREATE TYPE public.timer_type AS ENUM ('between_sets', 'between_exercises', 'custom');

-- externalRef.provider: an opaque lower-case slug, for example machines-atlas.
CREATE DOMAIN public.provider_slug AS text
  CHECK (VALUE ~ '^[a-z0-9]+(-[a-z0-9]+)*$');

-- ===============================================================
-- exercises
-- ===============================================================
CREATE TABLE public.exercises (
  id                uuid                 PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid                 REFERENCES public.users (id) ON DELETE CASCADE, -- NULL = catalogue
  name              text                 NOT NULL
    CHECK (char_length(btrim(name)) > 0 AND char_length(name) <= 200),
  type              public.exercise_type NOT NULL,
  equipment         public.equipment,
  setup_steps       text[]               CHECK (
    cardinality(setup_steps) > 0 AND array_ndims(setup_steps) = 1
    AND array_position(setup_steps, NULL) IS NULL AND array_position(setup_steps, '') IS NULL
  ),
  execution_steps   text[]               CHECK (
    cardinality(execution_steps) > 0 AND array_ndims(execution_steps) = 1
    AND array_position(execution_steps, NULL) IS NULL AND array_position(execution_steps, '') IS NULL
  ),
  tips              text[]               CHECK (
    cardinality(tips) > 0 AND array_ndims(tips) = 1
    AND array_position(tips, NULL) IS NULL AND array_position(tips, '') IS NULL
  ),
  image_uri         text                 CHECK (char_length(image_uri) > 0),
  video_uri         text                 CHECK (char_length(video_uri) > 0),
  external_provider public.provider_slug,
  external_id       text                 CHECK (char_length(external_id) BETWEEN 1 AND 200),
  created_at        timestamptz          NOT NULL DEFAULT now(),
  updated_at        timestamptz          NOT NULL DEFAULT now(),
  CONSTRAINT exercises_external_ref_complete CHECK ((external_provider IS NULL) = (external_id IS NULL)),
  CONSTRAINT exercises_external_ref_key UNIQUE (user_id, external_provider, external_id),
  -- The curated catalogue never holds provider items: imports are private rows.
  CONSTRAINT exercises_catalogue_has_no_external_ref
    CHECK (user_id IS NOT NULL OR (external_provider IS NULL AND external_id IS NULL))
);

COMMENT ON TABLE public.exercises IS 'Format "exercise". user_id NULL = curated catalogue, never with an externalRef.';

-- ===============================================================
-- exercise_muscle_groups (format exercise.muscleGroups[])
-- ===============================================================
CREATE TABLE public.exercise_muscle_groups (
  id          uuid                PRIMARY KEY DEFAULT gen_random_uuid(),
  exercise_id uuid                NOT NULL REFERENCES public.exercises (id) ON DELETE CASCADE,
  muscle      public.muscle_group NOT NULL,
  role        public.muscle_role  NOT NULL,
  created_at  timestamptz         NOT NULL DEFAULT now(),
  updated_at  timestamptz         NOT NULL DEFAULT now(),
  CONSTRAINT exercise_muscle_groups_key UNIQUE (exercise_id, muscle, role)
);

-- ===============================================================
-- routines and routine_items
-- ===============================================================
CREATE TABLE public.routines (
  id                uuid                 PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid                 NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  name              text                 NOT NULL CHECK (char_length(name) > 0),
  description       text,
  external_provider public.provider_slug,
  external_id       text                 CHECK (char_length(external_id) BETWEEN 1 AND 200),
  created_at        timestamptz          NOT NULL DEFAULT now(),
  updated_at        timestamptz          NOT NULL DEFAULT now(),
  CONSTRAINT routines_external_ref_complete CHECK ((external_provider IS NULL) = (external_id IS NULL)),
  CONSTRAINT routines_external_ref_key UNIQUE (user_id, external_provider, external_id),
  CONSTRAINT routines_id_user_key UNIQUE (id, user_id)
);

CREATE TABLE public.routine_items (
  id                      uuid               PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 uuid               NOT NULL,
  routine_id              uuid               NOT NULL,
  position                integer            NOT NULL CHECK (position >= 1),
  exercise_id             uuid               NOT NULL REFERENCES public.exercises (id) ON DELETE RESTRICT,
  target_sets             integer            CHECK (target_sets >= 1),
  target_reps_min         integer            CHECK (target_reps_min >= 1),
  target_reps_max         integer            CHECK (target_reps_max >= 1),
  target_weight           numeric(8, 3)      CHECK (target_weight >= 0),
  target_weight_unit      public.weight_unit,
  target_duration_seconds integer            CHECK (target_duration_seconds >= 0),
  rest_seconds            integer            CHECK (rest_seconds >= 0),
  notes                   text,
  created_at              timestamptz        NOT NULL DEFAULT now(),
  updated_at              timestamptz        NOT NULL DEFAULT now(),
  CONSTRAINT routine_items_routine_fkey FOREIGN KEY (routine_id, user_id)
    REFERENCES public.routines (id, user_id) ON DELETE CASCADE,
  CONSTRAINT routine_items_target_reps_complete CHECK ((target_reps_min IS NULL) = (target_reps_max IS NULL)),
  CONSTRAINT routine_items_target_reps_range CHECK (target_reps_min <= target_reps_max),
  CONSTRAINT routine_items_target_weight_complete CHECK ((target_weight IS NULL) = (target_weight_unit IS NULL)),
  -- Checked at statement end, so a single UPDATE can swap positions.
  CONSTRAINT routine_items_position_key UNIQUE (routine_id, position) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX routine_items_routine_user_idx ON public.routine_items (routine_id, user_id);
CREATE INDEX routine_items_user_id_idx ON public.routine_items (user_id);
CREATE INDEX routine_items_exercise_id_idx ON public.routine_items (exercise_id);

-- ===============================================================
-- sessions
-- ===============================================================
CREATE TABLE public.sessions (
  id                uuid                 PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid                 NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  routine_id        uuid,
  name              text,
  notes             text,
  started_at        timestamptz,
  completed_at      timestamptz          NOT NULL,
  time_zone         text                 NOT NULL
    CHECK (time_zone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+-]+)+$|^UTC$'),
  duration_seconds  integer              CHECK (duration_seconds >= 0),
  external_provider public.provider_slug,
  external_id       text                 CHECK (char_length(external_id) BETWEEN 1 AND 200),
  created_at        timestamptz          NOT NULL DEFAULT now(),
  updated_at        timestamptz          NOT NULL DEFAULT now(),
  CONSTRAINT sessions_routine_fkey FOREIGN KEY (routine_id, user_id)
    REFERENCES public.routines (id, user_id) ON DELETE SET NULL (routine_id),
  CONSTRAINT sessions_started_before_completed CHECK (started_at <= completed_at),
  CONSTRAINT sessions_duration_fits CHECK (
    started_at IS NULL OR duration_seconds IS NULL
    OR duration_seconds <= extract(epoch FROM completed_at - started_at)
  ),
  CONSTRAINT sessions_external_ref_complete CHECK ((external_provider IS NULL) = (external_id IS NULL)),
  CONSTRAINT sessions_external_ref_key UNIQUE (user_id, external_provider, external_id),
  CONSTRAINT sessions_id_user_key UNIQUE (id, user_id)
);

CREATE INDEX sessions_user_completed_idx ON public.sessions (user_id, completed_at DESC);
CREATE INDEX sessions_routine_user_idx ON public.sessions (routine_id, user_id);

-- ===============================================================
-- entries (one exercise inside a session)
-- ===============================================================
CREATE TABLE public.entries (
  id                        uuid                           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   uuid                           NOT NULL,
  session_id                uuid                           NOT NULL,
  position                  integer                        NOT NULL CHECK (position >= 1),
  exercise_id               uuid                           NOT NULL REFERENCES public.exercises (id) ON DELETE RESTRICT,
  status                    public.entry_status            NOT NULL,
  replaced_exercise_id      uuid                           REFERENCES public.exercises (id) ON DELETE RESTRICT,
  completed_at              timestamptz,
  notes                     text,
  reconciliation_keep       public.set_source,
  reconciliation_decided_by public.reconciliation_decider,
  reconciliation_decided_at timestamptz,
  external_provider         public.provider_slug,
  external_id               text                           CHECK (char_length(external_id) BETWEEN 1 AND 200),
  created_at                timestamptz                    NOT NULL DEFAULT now(),
  updated_at                timestamptz                    NOT NULL DEFAULT now(),
  CONSTRAINT entries_session_fkey FOREIGN KEY (session_id, user_id)
    REFERENCES public.sessions (id, user_id) ON DELETE CASCADE,
  CONSTRAINT entries_reconciliation_complete
    CHECK ((reconciliation_keep IS NULL) = (reconciliation_decided_by IS NULL)),
  CONSTRAINT entries_reconciliation_decided_at
    CHECK (reconciliation_decided_at IS NULL OR reconciliation_keep IS NOT NULL),
  -- "A default decision always keeps the imported sets."
  CONSTRAINT entries_reconciliation_default_keeps_imported
    CHECK (reconciliation_decided_by IS DISTINCT FROM 'default' OR reconciliation_keep = 'imported'),
  CONSTRAINT entries_external_ref_complete CHECK ((external_provider IS NULL) = (external_id IS NULL)),
  CONSTRAINT entries_external_ref_key UNIQUE (user_id, external_provider, external_id),
  CONSTRAINT entries_id_user_key UNIQUE (id, user_id),
  CONSTRAINT entries_position_key UNIQUE (session_id, position) DEFERRABLE INITIALLY IMMEDIATE
);

-- one-entry-per-exercise: at most one done entry per exercise in a session.
-- user_id is implied by session_id (composite FK), so it does not change the
-- rule. It keeps another user's entry from colliding here: such an insert must
-- fail on the session foreign key, not reveal what that session holds.
CREATE UNIQUE INDEX entries_one_done_per_exercise
  ON public.entries (session_id, user_id, exercise_id)
  WHERE status = 'done';

CREATE INDEX entries_session_user_idx ON public.entries (session_id, user_id);
CREATE INDEX entries_exercise_id_idx ON public.entries (exercise_id);
CREATE INDEX entries_replaced_exercise_id_idx ON public.entries (replaced_exercise_id)
  WHERE replaced_exercise_id IS NOT NULL;

-- ===============================================================
-- sets (strength, bodyweight and cardio)
-- ===============================================================
CREATE TABLE public.sets (
  id                uuid                 PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid                 NOT NULL,
  entry_id          uuid                 NOT NULL,
  position          integer              NOT NULL CHECK (position >= 1),
  source            public.set_source    NOT NULL,
  reps              integer              CHECK (reps >= 0),
  weight            numeric(8, 3)        CHECK (weight >= 0),
  weight_unit       public.weight_unit,
  duration_seconds  integer              CHECK (duration_seconds >= 0),
  distance_meters   numeric(10, 2)       CHECK (distance_meters >= 0),
  rir               integer              CHECK (rir BETWEEN 0 AND 10),
  rest_seconds      integer              CHECK (rest_seconds >= 0),
  completed_at      timestamptz,
  superseded        boolean              NOT NULL DEFAULT false,
  warmup            boolean              NOT NULL DEFAULT false,
  external_provider public.provider_slug,
  external_id       text                 CHECK (char_length(external_id) BETWEEN 1 AND 200),
  created_at        timestamptz          NOT NULL DEFAULT now(),
  updated_at        timestamptz          NOT NULL DEFAULT now(),
  CONSTRAINT sets_entry_fkey FOREIGN KEY (entry_id, user_id)
    REFERENCES public.entries (id, user_id) ON DELETE CASCADE,
  CONSTRAINT sets_reps_or_duration CHECK (reps IS NOT NULL OR duration_seconds IS NOT NULL),
  CONSTRAINT sets_distance_needs_duration CHECK (distance_meters IS NULL OR duration_seconds IS NOT NULL),
  CONSTRAINT sets_weight_complete CHECK ((weight IS NULL) = (weight_unit IS NULL)),
  CONSTRAINT sets_imported_needs_external_ref CHECK (source <> 'imported' OR external_id IS NOT NULL),
  CONSTRAINT sets_external_ref_complete CHECK ((external_provider IS NULL) = (external_id IS NULL)),
  CONSTRAINT sets_external_ref_key UNIQUE (user_id, external_provider, external_id),
  -- Position among the sets of the same source in the entry.
  CONSTRAINT sets_position_key UNIQUE (entry_id, source, position) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX sets_entry_user_idx ON public.sets (entry_id, user_id);

-- ===============================================================
-- rest_timers (cross-device rest timer, read through Realtime)
-- ===============================================================
-- session_id has no foreign key on purpose: a session row exists only once it
-- is completed (completed_at is required), while a timer runs during it.
CREATE TABLE public.rest_timers (
  id               uuid              PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid              NOT NULL DEFAULT auth.uid() REFERENCES public.users (id) ON DELETE CASCADE,
  session_id       uuid              NOT NULL,
  timer_type       public.timer_type NOT NULL,
  duration_seconds integer           NOT NULL CHECK (duration_seconds >= 0),
  started_at       timestamptz       NOT NULL DEFAULT now(),
  ends_at          timestamptz       NOT NULL,
  is_active        boolean           NOT NULL DEFAULT true,
  created_at       timestamptz       NOT NULL DEFAULT now(),
  updated_at       timestamptz       NOT NULL DEFAULT now(),
  CONSTRAINT rest_timers_ends_after_start CHECK (ends_at >= started_at)
);

-- Scoped per user: session_id has no FK, so it must not let one user block another.
CREATE UNIQUE INDEX rest_timers_one_active_per_session
  ON public.rest_timers (user_id, session_id)
  WHERE is_active;

ALTER PUBLICATION supabase_realtime ADD TABLE public.rest_timers;

-- ===============================================================
-- Validation triggers: rules that span tables
-- ===============================================================

-- exercise-type and entry status rules for a set.
CREATE FUNCTION public.tg_sets_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_type   public.exercise_type;
  v_status public.entry_status;
BEGIN
  SELECT x.type, e.status
    INTO v_type, v_status
    FROM public.entries e
    JOIN public.exercises x ON x.id = e.exercise_id
   WHERE e.id = NEW.entry_id;

  IF NOT FOUND THEN
    RETURN NEW; -- the foreign key reports a missing entry
  END IF;

  IF v_status = 'skipped' THEN
    RAISE EXCEPTION 'a skipped entry has no sets' USING ERRCODE = 'check_violation';
  END IF;

  IF v_type = 'cardio' THEN
    IF NEW.duration_seconds IS NULL OR NEW.reps IS NOT NULL OR NEW.weight IS NOT NULL THEN
      RAISE EXCEPTION 'cardio sets have a duration and neither reps nor weight'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.distance_meters IS NOT NULL THEN
    RAISE EXCEPTION 'only cardio sets have a distance' USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END
$$;

CREATE TRIGGER validate_set
  BEFORE INSERT OR UPDATE ON public.sets
  FOR EACH ROW EXECUTE FUNCTION public.tg_sets_validate();

-- No entry is completed after its session; an entry with sets is never skipped.
CREATE FUNCTION public.tg_entries_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_type public.exercise_type;
BEGIN
  IF NEW.completed_at IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.sessions s
     WHERE s.id = NEW.session_id AND NEW.completed_at > s.completed_at
  ) THEN
    RAISE EXCEPTION 'no entry is completed after its session' USING ERRCODE = 'check_violation';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.status = 'skipped' AND EXISTS (
    SELECT 1 FROM public.sets st WHERE st.entry_id = NEW.id
  ) THEN
    RAISE EXCEPTION 'a skipped entry has no sets' USING ERRCODE = 'check_violation';
  END IF;

  -- exercise-type: the sets already stored must fit the new exercise.
  IF TG_OP = 'UPDATE' AND NEW.exercise_id IS DISTINCT FROM OLD.exercise_id THEN
    SELECT x.type INTO v_type FROM public.exercises x WHERE x.id = NEW.exercise_id;
    IF v_type = 'cardio' AND EXISTS (
      SELECT 1 FROM public.sets st
       WHERE st.entry_id = NEW.id
         AND (st.duration_seconds IS NULL OR st.reps IS NOT NULL OR st.weight IS NOT NULL)
    ) THEN
      RAISE EXCEPTION 'cardio sets have a duration and neither reps nor weight'
        USING ERRCODE = 'check_violation';
    ELSIF v_type IS DISTINCT FROM 'cardio' AND EXISTS (
      SELECT 1 FROM public.sets st WHERE st.entry_id = NEW.id AND st.distance_meters IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'only cardio sets have a distance' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  RETURN NEW;
END
$$;

CREATE TRIGGER validate_entry
  BEFORE INSERT OR UPDATE ON public.entries
  FOR EACH ROW EXECUTE FUNCTION public.tg_entries_validate();

-- A session cannot end before one of its entries.
CREATE FUNCTION public.tg_sessions_validate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.entries e
     WHERE e.session_id = NEW.id AND e.completed_at > NEW.completed_at
  ) THEN
    RAISE EXCEPTION 'no entry is completed after its session' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER validate_session
  BEFORE UPDATE OF completed_at ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.tg_sessions_validate();

-- Account deletion. Exercises cascade from users, but history references them
-- with ON DELETE RESTRICT, and each cascade checks its references as soon as
-- it runs. Removing the user's sessions and routines first lets the whole
-- account go in one statement while an in-use exercise still cannot be
-- deleted on its own.
CREATE FUNCTION public.tg_users_delete_training_data()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
  DELETE FROM public.sessions WHERE user_id = OLD.id;
  DELETE FROM public.routines WHERE user_id = OLD.id;
  RETURN OLD;
END
$$;

CREATE TRIGGER delete_training_data
  BEFORE DELETE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.tg_users_delete_training_data();

-- ===============================================================
-- updated_at on every synced table (the app pulls by updated_at)
-- ===============================================================
ALTER FUNCTION public.tg_set_updated_at() SET search_path = '';

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'exercises', 'exercise_muscle_groups', 'routines', 'routine_items',
    'sessions', 'entries', 'sets', 'rest_timers'
  ] LOOP
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();', t);
  END LOOP;
END
$$;

-- ===============================================================
-- Row level security
-- ===============================================================
ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_muscle_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rest_timers ENABLE ROW LEVEL SECURITY;

-- users (kept table): same rules as before, with auth.uid() evaluated once
-- per statement and limited to signed-in callers.
DROP POLICY "users: select own" ON public.users;
DROP POLICY "users: insert own" ON public.users;
DROP POLICY "users: update own" ON public.users;
DROP POLICY "users: delete own" ON public.users;
CREATE POLICY "users: select own" ON public.users
  FOR SELECT TO authenticated USING (id = (SELECT auth.uid()));
CREATE POLICY "users: insert own" ON public.users
  FOR INSERT TO authenticated WITH CHECK (id = (SELECT auth.uid()));
CREATE POLICY "users: update own" ON public.users
  FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));
CREATE POLICY "users: delete own" ON public.users
  FOR DELETE TO authenticated USING (id = (SELECT auth.uid()));

-- exercises: own rows plus the read-only catalogue
CREATE POLICY "exercises: select own or catalogue" ON public.exercises
  FOR SELECT TO authenticated
  USING (user_id IS NULL OR user_id = (SELECT auth.uid()));
CREATE POLICY "exercises: insert own" ON public.exercises
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "exercises: update own" ON public.exercises
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY "exercises: delete own" ON public.exercises
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- exercise_muscle_groups: follow the exercise (the subquery applies exercises' RLS)
CREATE POLICY "exercise_muscle_groups: select via exercise" ON public.exercise_muscle_groups
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = exercise_id));
CREATE POLICY "exercise_muscle_groups: insert via own exercise" ON public.exercise_muscle_groups
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.exercises e WHERE e.id = exercise_id AND e.user_id = (SELECT auth.uid())
  ));
CREATE POLICY "exercise_muscle_groups: update via own exercise" ON public.exercise_muscle_groups
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.exercises e WHERE e.id = exercise_id AND e.user_id = (SELECT auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.exercises e WHERE e.id = exercise_id AND e.user_id = (SELECT auth.uid())
  ));
CREATE POLICY "exercise_muscle_groups: delete via own exercise" ON public.exercise_muscle_groups
  FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.exercises e WHERE e.id = exercise_id AND e.user_id = (SELECT auth.uid())
  ));

-- routines, sessions, sets, rest_timers: own rows only
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['routines', 'sessions', 'sets', 'rest_timers'] LOOP
    EXECUTE format(
      'CREATE POLICY "%1$s: select own" ON public.%1$I FOR SELECT TO authenticated
         USING (user_id = (SELECT auth.uid()));', t);
    EXECUTE format(
      'CREATE POLICY "%1$s: insert own" ON public.%1$I FOR INSERT TO authenticated
         WITH CHECK (user_id = (SELECT auth.uid()));', t);
    EXECUTE format(
      'CREATE POLICY "%1$s: update own" ON public.%1$I FOR UPDATE TO authenticated
         USING (user_id = (SELECT auth.uid())) WITH CHECK (user_id = (SELECT auth.uid()));', t);
    EXECUTE format(
      'CREATE POLICY "%1$s: delete own" ON public.%1$I FOR DELETE TO authenticated
         USING (user_id = (SELECT auth.uid()));', t);
  END LOOP;
END
$$;

-- routine_items and entries: own rows that only name exercises the user can see
CREATE POLICY "routine_items: select own" ON public.routine_items
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY "routine_items: insert own" ON public.routine_items
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = exercise_id)
  );
CREATE POLICY "routine_items: update own" ON public.routine_items
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = exercise_id)
  );
CREATE POLICY "routine_items: delete own" ON public.routine_items
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "entries: select own" ON public.entries
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY "entries: insert own" ON public.entries
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = exercise_id)
    AND (replaced_exercise_id IS NULL
         OR EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = replaced_exercise_id))
  );
CREATE POLICY "entries: update own" ON public.entries
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = exercise_id)
    AND (replaced_exercise_id IS NULL
         OR EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = replaced_exercise_id))
  );
CREATE POLICY "entries: delete own" ON public.entries
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- ===============================================================
-- API role privileges (replaces PR #100)
-- Explicit per table: anon gets nothing, authenticated gets DML (rows are
-- limited by RLS), service_role gets DML for importers and admin work.
-- ===============================================================
GRANT USAGE ON SCHEMA public TO authenticated, service_role;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'users', 'exercises', 'exercise_muscle_groups', 'routines', 'routine_items',
    'sessions', 'entries', 'sets', 'rest_timers'
  ] LOOP
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated, service_role;', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO authenticated, service_role;', t);
  END LOOP;
END
$$;

-- Trigger functions are not part of the API.
REVOKE EXECUTE ON FUNCTION public.tg_set_updated_at() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_handle_new_auth_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_sets_validate() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_entries_validate() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_sessions_validate() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_users_delete_training_data() FROM PUBLIC, anon, authenticated;
