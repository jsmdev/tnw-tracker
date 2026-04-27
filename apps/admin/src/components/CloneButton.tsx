"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

interface Props {
  cloneUrl: string;
}

export function CloneButton({ cloneUrl }: Props) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleClone() {
    setLoading(true);
    const res = await fetch(cloneUrl, { method: "POST" });
    if (res.redirected) {
      router.push(new URL(res.url).pathname);
    } else {
      setLoading(false);
    }
  }

  return (
    <button
      onClick={handleClone}
      disabled={loading}
      className="text-sm text-gray-500 hover:text-gray-700 border border-gray-200 rounded-lg px-3 py-1.5 transition-colors disabled:opacity-50"
    >
      {loading ? "Clonando…" : "Clonar"}
    </button>
  );
}
