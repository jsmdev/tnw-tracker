-- Otorga DML a los roles del Data API (anon/authenticated) sobre el schema public.
--
-- En DB fresca (supabase db reset / CI), las tablas quedan sin SELECT/INSERT/
-- UPDATE/DELETE para `authenticated` y `anon` — solo heredan TRUNCATE/REFERENCES/
-- TRIGGER. Los tests pgTAP que hacen `SET ROLE authenticated` (reorder_items, rls)
-- fallan con "permission denied". En Supabase cloud el Data API aplica estos
-- grants automáticamente; localmente hay que declararlos explícitamente.
--
-- RLS ya está habilitado en estas tablas (migración 0007), así que el acceso por
-- fila sigue restringido: estos grants solo habilitan el acceso a nivel de tabla.

GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;

-- Tablas/secuencias/funciones futuras creadas por el rol que aplica migraciones.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
