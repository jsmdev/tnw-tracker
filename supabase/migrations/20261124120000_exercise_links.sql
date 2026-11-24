-- Migration: personal related links of an exercise (S10, AC5).
--
-- Next to the curated links of an exercise (exercises.related_links, which
-- everyone sees), each user can add their own links to external information
-- about it (a video, an article…). Only their owner ever sees them.
--
-- - User data outside the training data format, like exercise_settings: a
--   link points at a catalogue exercise or at one of the user's own, and is
--   never sent with the exercise.
-- - title and source are what the app shows; the url is https, as in
--   related_links. position orders a user's links of one exercise from 1;
--   ties keep id order.
-- - No uniqueness on url: two devices adding the same link offline would
--   otherwise wedge each other's push. The app refuses a duplicate on its own
--   device instead.
-- - Every deleted link leaves its owner a tombstone, through the generic
--   tg_record_tombstones (20261119120000_sync_tombstones.sql), including the
--   links deleted with their exercise: a link of a catalogue exercise belongs
--   to a user while its exercise belongs to nobody, so the exercise's
--   tombstone (there is none for the catalogue) cannot remove it on the
--   device. Writing a link again under the same id clears its owner's
--   tombstone, as for the other tables.

CREATE TABLE public.exercise_links (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL DEFAULT auth.uid() REFERENCES public.users (id) ON DELETE CASCADE,
  exercise_id uuid        NOT NULL REFERENCES public.exercises (id) ON DELETE CASCADE,
  title       text        NOT NULL CHECK (char_length(btrim(title)) > 0),
  url         text        NOT NULL CHECK (url ~ '^https://[^[:space:]]+$'),
  source      text        NOT NULL CHECK (char_length(btrim(source)) > 0),
  position    integer     NOT NULL DEFAULT 1 CHECK (position >= 1),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.exercise_links IS
  'Personal related links of an exercise (S10): seen only by their owner, outside the training data format.';

-- The cascade from exercises, and row-level security, the pull and the
-- cascade from users on the owner.
CREATE INDEX exercise_links_exercise_id_idx ON public.exercise_links (exercise_id);
CREATE INDEX exercise_links_user_id_idx ON public.exercise_links (user_id);

CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.exercise_links
  FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at();

-- ===============================================================
-- Tombstones
-- ===============================================================
ALTER TABLE public.tombstones DROP CONSTRAINT tombstones_table_name_check;
ALTER TABLE public.tombstones ADD CONSTRAINT tombstones_table_name_check
  CHECK (table_name IN (
    'exercises', 'routines', 'sessions', 'entries', 'sets',
    'exercise_muscle_groups', 'routine_items', 'exercise_settings',
    'exercise_links'
  ));

CREATE TRIGGER record_tombstones AFTER DELETE ON public.exercise_links
  REFERENCING OLD TABLE AS deleted
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_record_tombstones();
CREATE TRIGGER clear_tombstones AFTER INSERT ON public.exercise_links
  REFERENCING NEW TABLE AS inserted
  FOR EACH STATEMENT EXECUTE FUNCTION public.tg_clear_tombstones();

-- ===============================================================
-- Row level security and privileges
-- ===============================================================
ALTER TABLE public.exercise_links ENABLE ROW LEVEL SECURITY;

-- Own rows that only name exercises the user can see (the subquery applies
-- exercises' RLS), like exercise_settings.
CREATE POLICY "exercise_links: select own" ON public.exercise_links
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
CREATE POLICY "exercise_links: insert own" ON public.exercise_links
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = exercise_id)
  );
CREATE POLICY "exercise_links: update own" ON public.exercise_links
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = exercise_id)
  );
CREATE POLICY "exercise_links: delete own" ON public.exercise_links
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- anon gets nothing, authenticated gets DML (rows limited by RLS), the
-- service role gets DML for admin work.
REVOKE ALL ON TABLE public.exercise_links FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.exercise_links TO authenticated, service_role;
