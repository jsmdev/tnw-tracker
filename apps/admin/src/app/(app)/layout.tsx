import { createClient } from "@/lib/supabase/server";
import { requireUser } from "@/lib/auth";
import { Header } from "@/components/Header";
import { Sidebar } from "@/components/Sidebar";

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const user = await requireUser(supabase);

  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <div className="flex-1 flex flex-col">
        <Header user={user} />
        <main className="flex-1 p-8">{children}</main>
      </div>
    </div>
  );
}
