import type { SupabaseClient, User } from "@supabase/supabase-js";
import { redirect } from "next/navigation";

// ---------------------------------------------------------------------------
// OwnershipError
// Clase named para permitir instanceof en catch en los callsites.
// No expone userId para evitar filtros accidentales al cliente.
// ---------------------------------------------------------------------------
export class OwnershipError extends Error {
  readonly table: string;
  readonly id: string;

  constructor(table: string, id: string) {
    super(`No autorizado: ${table}/${id}`);
    this.name = "OwnershipError";
    this.table = table;
    this.id = id;
  }
}

// ---------------------------------------------------------------------------
// OwnableTable
// Tipo literal union — TypeScript valida call-sites en compile time.
// Las junction tables (session_exercises, etc.) no van aquí: se valida
// a través de su parent (sessions, routines, plans).
// ---------------------------------------------------------------------------
export type OwnableTable = "exercises" | "plans" | "routines" | "sessions" | "exercise_videos";

// ---------------------------------------------------------------------------
// requireUser
// Devuelve el user autenticado o llama redirect("/login") si no hay sesión.
// Como redirect() lanza internamente, la firma Promise<User> es correcta:
// el happy path siempre resuelve con un User válido.
// ---------------------------------------------------------------------------
export async function requireUser(supabase: SupabaseClient): Promise<User> {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    redirect("/login");
  }

  return user;
}

// ---------------------------------------------------------------------------
// requireOwnership
// Verifica que el record <table>/<id> pertenece a userId.
// Caso especial exercise_videos: el user_id está en la tabla exercises (JOIN).
// Lanza OwnershipError si el record no existe, no pertenece al user, o hay error de DB.
// ---------------------------------------------------------------------------
export async function requireOwnership(
  supabase: SupabaseClient,
  table: OwnableTable,
  id: string,
  userId: string
): Promise<void> {
  if (table === "exercise_videos") {
    // exercise_videos no tiene user_id directo — pertenece a un exercise del user.
    // Query: SELECT exercises.id FROM exercises JOIN exercise_videos
    //          WHERE exercise_videos.id = $id AND exercises.user_id = $userId
    const { data, error } = await supabase
      .from("exercises")
      .select("id, exercise_videos!inner(id)")
      .eq("exercise_videos.id", id)
      .eq("user_id", userId)
      .maybeSingle();

    if (error || !data) {
      throw new OwnershipError(table, id);
    }
    return;
  }

  // Tablas directas: exercises, plans, routines, sessions
  const { data, error } = await supabase
    .from(table)
    .select("id")
    .eq("id", id)
    .eq("user_id", userId)
    .maybeSingle();

  if (error || !data) {
    throw new OwnershipError(table, id);
  }
}
