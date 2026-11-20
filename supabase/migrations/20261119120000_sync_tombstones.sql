-- Migration: server-side tombstones for the sync (issue #135, S11).
--
-- The app pulls changes by (updated_at, id), so a deleted row never shows up
-- in a pull. Every delete of a user-owned exercise, routine, session, entry or
-- set leaves a tombstone of the row's owner instead, whoever deleted it (the
-- app, another device, an importer with the service role) and through whatever
-- cascade (a session's entries and sets, an account's data). The app pages the
-- tombstones with the same keyset cursor as the rows (docs/database-schema.md,
-- "Sync").
--
-- - Catalogue exercises (user_id IS NULL) belong to nobody: no tombstone.
-- - Muscle groups and routine items are not tracked here: they have no owner
--   column and follow their exercise or routine.
-- - Writing a row again under the same id (a device that kept its pending
--   version of a row deleted elsewhere pushes it back) clears its tombstone,
--   so a pull never reads a tombstone of a row that exists again.
-- - The owner reads their tombstones; only these triggers write them. Clients
--   never write one, so a client cannot delete another device's live rows.

CREATE TABLE public.tombstones (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES public.users (id) ON DELETE CASCADE,
  table_name text        NOT NULL
    CHECK (table_name IN ('exercises', 'routines', 'sessions', 'entries', 'sets')),
  row_id     uuid        NOT NULL,
  -- When the row was deleted; also the tombstone's place in the pull.
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- The pull: one user's tombstones by (updated_at, id).
CREATE INDEX tombstones_user_cursor_idx ON public.tombstones (user_id, updated_at, id);
-- Clearing the tombstone of a row written again.
CREATE INDEX tombstones_row_idx ON public.tombstones (table_name, row_id);

-- ===============================================================
-- Triggers
-- ===============================================================

-- One tombstone per deleted row, of the row's owner. Statement level, so a
-- cascade of many rows is one insert. SECURITY DEFINER: the trigger is the only
-- writer, and a cascade runs it whichever role started the delete.
CREATE FUNCTION public.tg_record_tombstones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.tombstones (user_id, table_name, row_id)
  SELECT d.user_id, TG_TABLE_NAME, d.id
  FROM deleted d
  -- Only rows of an existing user: a catalogue exercise has no owner, and an
  -- account being deleted keeps no tombstones (its users row is already gone
  -- when the cascade from it reaches its exercises).
  WHERE EXISTS (SELECT 1 FROM public.users u WHERE u.id = d.user_id);
  RETURN NULL;
END
$$;

-- A row inserted again under a deleted id is no longer deleted. Only its
-- owner's tombstone goes: another user reusing the id clears nothing.
CREATE FUNCTION public.tg_clear_tombstones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  DELETE FROM public.tombstones t
  USING inserted i
  WHERE t.table_name = TG_TABLE_NAME AND t.row_id = i.id AND t.user_id = i.user_id;
  RETURN NULL;
END
$$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['exercises', 'routines', 'sessions', 'entries', 'sets'] LOOP
    EXECUTE format(
      'CREATE TRIGGER record_tombstones AFTER DELETE ON public.%I
         REFERENCING OLD TABLE AS deleted
         FOR EACH STATEMENT EXECUTE FUNCTION public.tg_record_tombstones();', t);
    EXECUTE format(
      'CREATE TRIGGER clear_tombstones AFTER INSERT ON public.%I
         REFERENCING NEW TABLE AS inserted
         FOR EACH STATEMENT EXECUTE FUNCTION public.tg_clear_tombstones();', t);
  END LOOP;
END
$$;

-- ===============================================================
-- Row level security and privileges
-- ===============================================================
ALTER TABLE public.tombstones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tombstones: select own" ON public.tombstones
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

REVOKE ALL ON TABLE public.tombstones FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.tombstones TO authenticated;
-- The service role reads them and may prune old ones.
GRANT SELECT, DELETE ON TABLE public.tombstones TO service_role;

-- Trigger functions are not part of the API.
REVOKE EXECUTE ON FUNCTION public.tg_record_tombstones() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_clear_tombstones() FROM PUBLIC, anon, authenticated;
