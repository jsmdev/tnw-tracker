"use client";
import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { createExerciseVideoAction } from "@/app/actions/exercise";

interface Props {
  exerciseId: string;
}

export function VideoUploader({ exerciseId }: Props) {
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [youtubeUrl, setYoutubeUrl] = useState("");
  const [tab, setTab] = useState<"file" | "youtube">("file");

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setError(null);

    const supabase = createClient();
    const ext = file.name.split(".").pop() ?? "mp4";
    const path = `${exerciseId}/${Date.now()}.${ext}`;

    const { data, error: uploadError } = await supabase.storage
      .from("exercise-videos")
      .upload(path, file);

    if (uploadError) {
      setError(uploadError.message);
      setUploading(false);
      return;
    }

    const {
      data: { publicUrl },
    } = supabase.storage.from("exercise-videos").getPublicUrl(data.path);

    const result = await createExerciseVideoAction(exerciseId, publicUrl, "storage");
    if (result.error) setError(result.error);

    e.target.value = "";
    setUploading(false);
  }

  async function handleYoutubeSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!youtubeUrl.trim()) return;

    setUploading(true);
    setError(null);

    const result = await createExerciseVideoAction(exerciseId, youtubeUrl.trim(), "youtube");
    if (result.error) {
      setError(result.error);
    } else {
      setYoutubeUrl("");
    }

    setUploading(false);
  }

  return (
    <div className="border border-gray-200 rounded-lg p-4">
      <div className="flex gap-2 mb-4">
        <button
          type="button"
          onClick={() => setTab("file")}
          className={`text-sm px-3 py-1.5 rounded-md font-medium transition-colors ${
            tab === "file" ? "bg-blue-100 text-blue-700" : "text-gray-500 hover:text-gray-700"
          }`}
        >
          Subir archivo
        </button>
        <button
          type="button"
          onClick={() => setTab("youtube")}
          className={`text-sm px-3 py-1.5 rounded-md font-medium transition-colors ${
            tab === "youtube" ? "bg-blue-100 text-blue-700" : "text-gray-500 hover:text-gray-700"
          }`}
        >
          URL de YouTube
        </button>
      </div>

      {tab === "file" && (
        <div>
          <input
            type="file"
            accept="video/*"
            onChange={handleFileChange}
            disabled={uploading}
            className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100 disabled:opacity-50"
          />
          <p className="mt-1 text-xs text-gray-400">
            MP4, MOV, WebM. Se sube al bucket exercise-videos.
          </p>
        </div>
      )}

      {tab === "youtube" && (
        <form onSubmit={handleYoutubeSubmit} className="flex gap-2">
          <input
            type="url"
            value={youtubeUrl}
            onChange={(e) => setYoutubeUrl(e.target.value)}
            placeholder="https://youtube.com/watch?v=..."
            disabled={uploading}
            className="flex-1 border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50"
          />
          <button
            type="submit"
            disabled={uploading || !youtubeUrl.trim()}
            className="bg-blue-600 text-white rounded-lg px-4 py-2 text-sm font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors"
          >
            {uploading ? "Guardando..." : "Añadir"}
          </button>
        </form>
      )}

      {uploading && tab === "file" && (
        <p className="mt-2 text-sm text-gray-500">Subiendo vídeo...</p>
      )}
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
    </div>
  );
}
