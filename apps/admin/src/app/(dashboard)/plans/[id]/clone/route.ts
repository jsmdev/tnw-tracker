import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";

export async function POST(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return new Response("Unauthorized", { status: 401 });

  const { data: plan } = await supabase.from("plans").select("name").eq("id", id).single();

  if (!plan) return new Response("Not found", { status: 404 });

  const { data: newId, error } = await supabase.rpc("clone_plan", {
    p_plan_id: id,
    p_new_name: `${plan.name} (copia)`,
  });

  if (error) return new Response(error.message, { status: 500 });

  redirect(`/dashboard/plans/${newId}`);
}
