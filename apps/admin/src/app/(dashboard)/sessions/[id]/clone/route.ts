import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

export async function POST(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return new Response("Unauthorized", { status: 401 });

  const { data: session } = await supabase.from("sessions").select("name").eq("id", id).single();

  if (!session) return new Response("Not found", { status: 404 });

  const { data: newId, error } = await supabase.rpc("clone_session", {
    p_session_id: id,
    p_new_name: `${session.name} (copia)`,
  });

  if (error) return new Response(error.message, { status: 500 });

  redirect(`/dashboard/sessions/${newId}`);
}
