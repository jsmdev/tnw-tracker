"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: "📊" },
  { href: "/dashboard/exercises", label: "Ejercicios", icon: "🏋️" },
  { href: "/dashboard/plans", label: "Planes", icon: "📋" },
  { href: "/dashboard/routines", label: "Rutinas", icon: "🔄" },
  { href: "/dashboard/sessions", label: "Sesiones", icon: "📅" },
  { href: "/dashboard/workouts", label: "Entrenamientos", icon: "⚡" },
  { href: "/dashboard/settings", label: "Ajustes", icon: "⚙️" },
];

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="w-56 shrink-0 bg-white border-r border-gray-200 min-h-screen flex flex-col">
      <div className="px-6 py-5 border-b border-gray-200">
        <span className="font-bold text-gray-900">TNW Tracker</span>
      </div>
      <nav className="flex-1 px-3 py-4 space-y-1">
        {navItems.map((item) => {
          const isActive = pathname === item.href || pathname.startsWith(item.href + "/");
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={isActive ? "page" : undefined}
              className={`flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                isActive
                  ? "bg-blue-50 text-blue-700"
                  : "text-gray-600 hover:bg-gray-100 hover:text-gray-900"
              }`}
            >
              <span>{item.icon}</span>
              {item.label}
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
