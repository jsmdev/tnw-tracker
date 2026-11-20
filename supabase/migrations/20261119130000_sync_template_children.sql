-- Migration: sync of exercise settings, muscle groups and routine items (issue #135, T6).
--
-- 1. exercise_muscle_groups.position keeps the order of an exercise's muscles
--    (format `exercise.muscleGroups[]` is a list), so it round-trips.
-- 2. Deleting a muscle group, a routine item or an exercise setting on its own
--    records a tombstone of its owner (20261119120000_sync_tombstones.sql), so
--    the app removes it too: a device that drops a muscle or shortens a
--    routine deletes those rows on the server, and the other devices follow.
--
-- - exercise_settings has no `id`: its key for the owner is `exercise_id`, so
--   its tombstone's row_id is the exercise id. The app pulls settings by
--   (updated_at, exercise_id) for the same reason.
-- - exercise_muscle_groups has no `user_id`: the owner is its exercise's. A
--   catalogue exercise's muscles belong to nobody and leave none.
-- - A row deleted together with its parent (the cascade from deleting an
--   exercise or a routine, or an account) leaves no tombstone of its own: the
--   parent's tombstone already removes it on the device.
-- - Inserting a row again under the same key clears its owner's tombstone, as
--   for the other tables.

-- ===============================================================
-- 1. Muscle group order
-- ===============================================================
ALTER TABLE public.exercise_muscle_groups
  ADD COLUMN position integer NOT NULL DEFAULT 1 CHECK (position >= 1);

COMMENT ON COLUMN public.exercise_muscle_groups.position IS
  'Order of the muscle in its exercise, from 1. Rows written without one (the seed) share 1 and keep id order.';

-- Existing rows: primary muscles first, then by muscle, so the order is stable.
UPDATE public.exercise_muscle_groups g
SET position = ordered.position
FROM (
  SELECT id, row_number() OVER (PARTITION BY exercise_id ORDER BY role, muscle, id)::int AS position
  FROM public.exercise_muscle_groups
) ordered
WHERE ordered.id = g.id AND g.position IS DISTINCT FROM ordered.position;

-- ===============================================================
-- 2. Tombstones of child rows
-- ===============================================================
ALTER TABLE public.tombstones DROP CONSTRAINT tombstones_table_name_check;
ALTER TABLE public.tombstones ADD CONSTRAINT tombstones_table_name_check
  CHECK (table_name IN (
    'exercises', 'routines', 'sessions', 'entries', 'sets',
    'exercise_muscle_groups', 'routine_items', 'exercise_settings'
  ));

-- One tombstone per child row deleted on its own, of its owner. Statement
-- level and SECURITY DEFINER, like tg_record_tombstones. At the end of a
-- cascaded delete the parent row is already gone, so the EXISTS on the parent
-- leaves out rows deleted with it.
CREATE FUNCTION public.tg_record_child_tombstones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_TABLE_NAME = 'exercise_muscle_groups' THEN
    INSERT INTO public.tombstones (user_id, table_name, row_id)
    SELECT e.user_id, TG_TABLE_NAME, d.id
    FROM deleted d
    JOIN public.exercises e ON e.id = d.exercise_id
    WHERE e.user_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = e.user_id);
  ELSIF TG_TABLE_NAME = 'routine_items' THEN
    INSERT INTO public.tombstones (user_id, table_name, row_id)
    SELECT d.user_id, TG_TABLE_NAME, d.id
    FROM deleted d
    WHERE EXISTS (SELECT 1 FROM public.routines r WHERE r.id = d.routine_id)
      AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = d.user_id);
  ELSIF TG_TABLE_NAME = 'exercise_settings' THEN
    INSERT INTO public.tombstones (user_id, table_name, row_id)
    SELECT d.user_id, TG_TABLE_NAME, d.exercise_id
    FROM deleted d
    WHERE EXISTS (SELECT 1 FROM public.exercises e WHERE e.id = d.exercise_id)
      AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = d.user_id);
  END IF;
  RETURN NULL;
END
$$;

-- A child row inserted again under a deleted key clears its owner's tombstone.
CREATE FUNCTION public.tg_clear_child_tombstones()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF TG_TABLE_NAME = 'exercise_muscle_groups' THEN
    DELETE FROM public.tombstones t
    USING inserted i
    JOIN public.exercises e ON e.id = i.exercise_id
    WHERE t.table_name = TG_TABLE_NAME AND t.row_id = i.id AND t.user_id = e.user_id;
  ELSIF TG_TABLE_NAME = 'routine_items' THEN
    DELETE FROM public.tombstones t
    USING inserted i
    WHERE t.table_name = TG_TABLE_NAME AND t.row_id = i.id AND t.user_id = i.user_id;
  ELSIF TG_TABLE_NAME = 'exercise_settings' THEN
    DELETE FROM public.tombstones t
    USING inserted i
    WHERE t.table_name = TG_TABLE_NAME AND t.row_id = i.exercise_id AND t.user_id = i.user_id;
  END IF;
  RETURN NULL;
END
$$;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['exercise_muscle_groups', 'routine_items', 'exercise_settings'] LOOP
    EXECUTE format(
      'CREATE TRIGGER record_tombstones AFTER DELETE ON public.%I
         REFERENCING OLD TABLE AS deleted
         FOR EACH STATEMENT EXECUTE FUNCTION public.tg_record_child_tombstones();', t);
    EXECUTE format(
      'CREATE TRIGGER clear_tombstones AFTER INSERT ON public.%I
         REFERENCING NEW TABLE AS inserted
         FOR EACH STATEMENT EXECUTE FUNCTION public.tg_clear_child_tombstones();', t);
  END LOOP;
END
$$;

-- Trigger functions are not part of the API.
REVOKE EXECUTE ON FUNCTION public.tg_record_child_tombstones() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.tg_clear_child_tombstones() FROM PUBLIC, anon, authenticated;
