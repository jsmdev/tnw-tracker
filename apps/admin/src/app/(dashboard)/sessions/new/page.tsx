import Link from "next/link";
import { SessionForm } from "@/components/session/SessionForm";

export default function NewSessionPage() {
  return (
    <div className="max-w-2xl">
      <div className="flex items-center gap-3 mb-6">
        <Link href="/dashboard/sessions" className="text-gray-400 hover:text-gray-600 text-sm">
          ← Sesiones
        </Link>
        <span className="text-gray-300">/</span>
        <h1 className="text-2xl font-bold text-gray-900">Nueva sesión</h1>
      </div>

      <div className="bg-white rounded-xl shadow p-8">
        <SessionForm />
      </div>
    </div>
  );
}
