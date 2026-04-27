-- Función invocable via RPC para refrescar la vista materializada semanal.
-- Solo accesible con service_role (la Edge Function aggregate_metrics la llama).
CREATE OR REPLACE FUNCTION public.refresh_mv_weekly_volume()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_user_weekly_volume;
END $$;
