/**
 * Seed script for E2E tests — creates a test user via Supabase auth.admin.
 *
 * Idempotente: si el usuario ya existe, no falla.
 *
 * Requisitos:
 *   - SUPABASE_SERVICE_ROLE_KEY en el entorno (o usar el default local)
 *   - Supabase local corriendo (`supabase start`)
 *
 * Uso:
 *   node supabase/tests/seed-e2e.mjs
 */

import { createClient } from "@supabase/supabase-js";

const url = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!key) {
  console.error("SUPABASE_SERVICE_ROLE_KEY es requerido");
  process.exit(1);
}

const supabase = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const { data, error } = await supabase.auth.admin.createUser({
  email: "e2e@test.local",
  password: "Dev1234!",
  email_confirm: true,
  app_metadata: { role: "owner" },
});

if (error?.message?.includes("already been registered")) {
  console.log("Usuario e2e ya existe, omitiendo creación.");
  process.exit(0);
}

if (error) {
  console.error("Error al crear usuario e2e:", error.message);
  process.exit(1);
}

console.log("Usuario e2e creado:", data.user.id);
