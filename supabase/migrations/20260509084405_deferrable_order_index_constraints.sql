-- Make UNIQUE (parent_id, order_index) constraints on junction tables DEFERRABLE.
--
-- Why: PostgreSQL evaluates UNIQUE constraints per-row during UPDATE, not at
-- end-of-statement (verified during sdd-verify of admin-quality-pass).
-- The reorder_items RPC uses UPDATE FROM jsonb_to_recordset to swap
-- order_index values atomically; without DEFERRABLE constraints, an intermediate
-- row update may transiently violate the UNIQUE constraint and abort the
-- statement even though the final state would be valid.
--
-- Strategy: DEFERRABLE INITIALLY IMMEDIATE (not DEFERRED).
-- This preserves default immediate-check semantics (INSERT conflicts still fail fast),
-- while allowing the reorder_items RPC to issue SET CONSTRAINTS ... DEFERRED
-- inside its transaction to defer the check until COMMIT.

ALTER TABLE public.session_exercises
  DROP CONSTRAINT session_exercises_session_id_order_index_key,
  ADD CONSTRAINT session_exercises_session_id_order_index_key
    UNIQUE (session_id, order_index) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE public.routine_sessions
  DROP CONSTRAINT routine_sessions_routine_id_order_index_key,
  ADD CONSTRAINT routine_sessions_routine_id_order_index_key
    UNIQUE (routine_id, order_index) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE public.plan_routines
  DROP CONSTRAINT plan_routines_plan_id_order_index_key,
  ADD CONSTRAINT plan_routines_plan_id_order_index_key
    UNIQUE (plan_id, order_index) DEFERRABLE INITIALLY IMMEDIATE;
