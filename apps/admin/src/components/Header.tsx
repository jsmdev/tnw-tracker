import type { User } from "@supabase/supabase-js";
import { LogoutButton } from "@/components/LogoutButton";

interface HeaderProps {
  user: User;
}

export function Header({ user }: HeaderProps) {
  return (
    <header className="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between">
      <span className="text-sm text-gray-600">{user.email}</span>
      <LogoutButton />
    </header>
  );
}
