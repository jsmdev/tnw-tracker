"use client";

import Link from "next/link";

interface ErrorBoundaryProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function DashboardError({ error, reset }: ErrorBoundaryProps) {
  return (
    <div className="flex min-h-screen items-center justify-center p-8">
      <div className="max-w-md text-center space-y-4">
        <h2 className="text-xl font-semibold text-gray-900">Algo salió mal</h2>
        {process.env.NODE_ENV === "development" && (
          <p className="text-sm text-gray-500 font-mono break-all">{error.message}</p>
        )}
        <div className="flex items-center justify-center gap-3">
          <button
            type="button"
            onClick={reset}
            className="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 transition-colors"
          >
            Reintentar
          </button>
          <Link href="/dashboard" className="text-sm text-gray-600 hover:text-gray-900 font-medium">
            Volver al dashboard
          </Link>
        </div>
      </div>
    </div>
  );
}
