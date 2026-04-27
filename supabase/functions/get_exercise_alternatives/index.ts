import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "GET") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return new Response("Unauthorized", { status: 401 });

  const url = new URL(req.url);
  const exerciseId = url.searchParams.get("exercise_id");
  const limitParam = url.searchParams.get("limit");

  if (!exerciseId) {
    return new Response("exercise_id required", { status: 400 });
  }

  const limit = Math.min(Math.max(parseInt(limitParam ?? "5", 10), 1), 20);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, authHeader.replace("Bearer ", ""), {
    global: { headers: { Authorization: authHeader } },
  });

  const {
    data: { user },
    error: authError,
  } = await sb.auth.getUser();

  if (authError || !user) return new Response("Unauthorized", { status: 401 });

  const { data, error } = await sb.rpc("get_exercise_alternatives", {
    p_user_id: user.id,
    p_exercise_id: exerciseId,
    p_limit: limit,
  });

  if (error) return new Response(error.message, { status: 400 });

  return Response.json(data ?? []);
});
