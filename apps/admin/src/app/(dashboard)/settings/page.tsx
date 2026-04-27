import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { SettingsForm } from "@/components/SettingsForm";

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("users")
    .select("weight_unit, timer_trigger_mode")
    .eq("id", user.id)
    .single();

  const weightUnit = (profile?.weight_unit ?? "kg") as "kg" | "lb";
  const timerTriggerMode = (profile?.timer_trigger_mode ?? "auto") as "auto" | "manual";

  return (
    <div className="max-w-md">
      <h1 className="text-2xl font-bold text-gray-900 mb-6">Ajustes</h1>

      <div className="bg-white rounded-xl shadow p-6">
        <SettingsForm weightUnit={weightUnit} timerTriggerMode={timerTriggerMode} />
      </div>
    </div>
  );
}
