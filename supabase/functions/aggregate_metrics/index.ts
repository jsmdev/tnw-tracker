import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Sólo service role puede invocar esto
  const authHeader = req.headers.get("Authorization");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!authHeader || authHeader !== `Bearer ${serviceRoleKey}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, serviceRoleKey);

  const { error } = await sb.rpc("refresh_mv_weekly_volume");

  if (error) {
    return new Response(error.message, { status: 500 });
  }

  return Response.json({ refreshed: true });
});
