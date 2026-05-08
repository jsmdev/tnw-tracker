-- Migration: reorder_items RPC — atomic reorder for junction tables
-- REQ-RPC-001: SECURITY INVOKER, whitelist de tablas
-- REQ-RPC-002: valida ownership del parent contra auth.uid()
-- REQ-RPC-003: UPDATE atómico via UPDATE FROM jsonb_to_recordset (una sola sentencia)
-- REQ-RPC-004: respeta UNIQUE sin fase negativa (PostgreSQL evalúa UNIQUE al final del statement)

CREATE OR REPLACE FUNCTION public.reorder_items(
  p_table       text,
  p_parent_col  text,
  p_parent_id   uuid,
  p_items       jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_parent_table text;
  v_owner_check  boolean;
  v_item         jsonb;
BEGIN
  -- ALLOWED TABLES: session_exercises, routine_sessions, plan_routines
  CASE p_table
    WHEN 'session_exercises' THEN v_parent_table := 'sessions';
    WHEN 'routine_sessions'  THEN v_parent_table := 'routines';
    WHEN 'plan_routines'     THEN v_parent_table := 'plans';
    ELSE RAISE EXCEPTION 'invalid_table';
  END CASE;

  -- Validate p_parent_col matches the allowed column for the given table
  IF (p_table = 'session_exercises' AND p_parent_col != 'session_id') OR
     (p_table = 'routine_sessions'  AND p_parent_col != 'routine_id') OR
     (p_table = 'plan_routines'     AND p_parent_col != 'plan_id') THEN
    RAISE EXCEPTION 'invalid_payload';
  END IF;

  -- Validate jsonb shape: must be a non-empty array
  IF jsonb_typeof(p_items) != 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'invalid_payload';
  END IF;

  -- Validate each element has required keys: id (non-null) and order_index (non-null integer)
  FOR v_item IN SELECT jsonb_array_elements(p_items)
  LOOP
    IF (v_item->>'id') IS NULL OR (v_item->>'order_index') IS NULL THEN
      RAISE EXCEPTION 'invalid_payload';
    END IF;
    -- Validate order_index is a valid integer (not a string like 'abc')
    PERFORM (v_item->>'order_index')::int;
  END LOOP;

  -- Validate ownership of the parent record
  EXECUTE format(
    'SELECT EXISTS(SELECT 1 FROM %I WHERE id = $1 AND user_id = $2)',
    v_parent_table
  ) INTO v_owner_check USING p_parent_id, auth.uid();

  IF NOT v_owner_check THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  -- Atomic reorder: UPDATE FROM jsonb_to_recordset in a single statement
  -- PostgreSQL evaluates UNIQUE constraints at end of statement — no negative phase needed
  EXECUTE format(
    'UPDATE %I AS t
     SET order_index = v.order_index
     FROM jsonb_to_recordset($1) AS v(id uuid, order_index int)
     WHERE t.id = v.id
       AND t.%I = $2',
    p_table, p_parent_col
  ) USING p_items, p_parent_id;

EXCEPTION
  WHEN invalid_text_representation OR datatype_mismatch THEN
    RAISE EXCEPTION 'invalid_payload';
END;
$$;

COMMENT ON FUNCTION public.reorder_items(text, text, uuid, jsonb) IS
  'Atomic reorder for junction tables. Allowed tables: session_exercises, routine_sessions, plan_routines. Validates parent ownership via auth.uid(). No negative phase required — PostgreSQL UNIQUE is evaluated at statement end.';

GRANT EXECUTE ON FUNCTION public.reorder_items(text, text, uuid, jsonb) TO authenticated;
