export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      exercise_sets: {
        Row: {
          completed_at: string | null
          created_at: string
          id: string
          is_personal_record: boolean
          is_warmup: boolean
          notes: string | null
          reps: number | null
          rpe: number | null
          set_number: number
          weight: number | null
          weight_unit: Database["public"]["Enums"]["weight_unit"]
          workout_exercise_id: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          id?: string
          is_personal_record?: boolean
          is_warmup?: boolean
          notes?: string | null
          reps?: number | null
          rpe?: number | null
          set_number: number
          weight?: number | null
          weight_unit?: Database["public"]["Enums"]["weight_unit"]
          workout_exercise_id: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          id?: string
          is_personal_record?: boolean
          is_warmup?: boolean
          notes?: string | null
          reps?: number | null
          rpe?: number | null
          set_number?: number
          weight?: number | null
          weight_unit?: Database["public"]["Enums"]["weight_unit"]
          workout_exercise_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "exercise_sets_workout_exercise_id_fkey"
            columns: ["workout_exercise_id"]
            isOneToOne: false
            referencedRelation: "workout_exercises"
            referencedColumns: ["id"]
          },
        ]
      }
      exercise_videos: {
        Row: {
          created_at: string
          exercise_id: string
          id: string
          is_downloadable: boolean
          order_index: number
          source: Database["public"]["Enums"]["video_source"]
          url: string
        }
        Insert: {
          created_at?: string
          exercise_id: string
          id?: string
          is_downloadable?: boolean
          order_index?: number
          source: Database["public"]["Enums"]["video_source"]
          url: string
        }
        Update: {
          created_at?: string
          exercise_id?: string
          id?: string
          is_downloadable?: boolean
          order_index?: number
          source?: Database["public"]["Enums"]["video_source"]
          url?: string
        }
        Relationships: [
          {
            foreignKeyName: "exercise_videos_exercise_id_fkey"
            columns: ["exercise_id"]
            isOneToOne: false
            referencedRelation: "exercises"
            referencedColumns: ["id"]
          },
        ]
      }
      exercises: {
        Row: {
          category: Database["public"]["Enums"]["exercise_category"]
          created_at: string
          id: string
          instructions: string | null
          is_active: boolean
          is_public: boolean
          muscle_groups: string[]
          name: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          category: Database["public"]["Enums"]["exercise_category"]
          created_at?: string
          id?: string
          instructions?: string | null
          is_active?: boolean
          is_public?: boolean
          muscle_groups?: string[]
          name: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          category?: Database["public"]["Enums"]["exercise_category"]
          created_at?: string
          id?: string
          instructions?: string | null
          is_active?: boolean
          is_public?: boolean
          muscle_groups?: string[]
          name?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "exercises_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      motivational_quotes: {
        Row: {
          author: string | null
          content: string
          created_at: string
          id: string
        }
        Insert: {
          author?: string | null
          content: string
          created_at?: string
          id?: string
        }
        Update: {
          author?: string | null
          content?: string
          created_at?: string
          id?: string
        }
        Relationships: []
      }
      personal_records: {
        Row: {
          achieved_at: string
          created_at: string
          exercise_id: string
          exercise_set_id: string | null
          id: string
          record_type: Database["public"]["Enums"]["pr_record_type"]
          user_id: string
          value: number
          weight_unit: Database["public"]["Enums"]["weight_unit"]
        }
        Insert: {
          achieved_at: string
          created_at?: string
          exercise_id: string
          exercise_set_id?: string | null
          id?: string
          record_type: Database["public"]["Enums"]["pr_record_type"]
          user_id: string
          value: number
          weight_unit?: Database["public"]["Enums"]["weight_unit"]
        }
        Update: {
          achieved_at?: string
          created_at?: string
          exercise_id?: string
          exercise_set_id?: string | null
          id?: string
          record_type?: Database["public"]["Enums"]["pr_record_type"]
          user_id?: string
          value?: number
          weight_unit?: Database["public"]["Enums"]["weight_unit"]
        }
        Relationships: [
          {
            foreignKeyName: "personal_records_exercise_id_fkey"
            columns: ["exercise_id"]
            isOneToOne: false
            referencedRelation: "exercises"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "personal_records_exercise_set_id_fkey"
            columns: ["exercise_set_id"]
            isOneToOne: false
            referencedRelation: "exercise_sets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "personal_records_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      plan_routines: {
        Row: {
          created_at: string
          id: string
          order_index: number
          plan_id: string
          routine_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          order_index: number
          plan_id: string
          routine_id: string
        }
        Update: {
          created_at?: string
          id?: string
          order_index?: number
          plan_id?: string
          routine_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "plan_routines_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "plan_routines_routine_id_fkey"
            columns: ["routine_id"]
            isOneToOne: false
            referencedRelation: "routines"
            referencedColumns: ["id"]
          },
        ]
      }
      plans: {
        Row: {
          created_at: string
          description: string | null
          duration_weeks: number | null
          id: string
          is_active: boolean
          is_public: boolean
          name: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          duration_weeks?: number | null
          id?: string
          is_active?: boolean
          is_public?: boolean
          name: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          description?: string | null
          duration_weeks?: number | null
          id?: string
          is_active?: boolean
          is_public?: boolean
          name?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "plans_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      rest_timers: {
        Row: {
          created_at: string
          duration_seconds: number
          ends_at: string
          exercise_id: string | null
          id: string
          is_active: boolean
          set_number: number | null
          started_at: string
          timer_type: Database["public"]["Enums"]["timer_type"]
          workout_id: string
        }
        Insert: {
          created_at?: string
          duration_seconds: number
          ends_at: string
          exercise_id?: string | null
          id?: string
          is_active?: boolean
          set_number?: number | null
          started_at?: string
          timer_type: Database["public"]["Enums"]["timer_type"]
          workout_id: string
        }
        Update: {
          created_at?: string
          duration_seconds?: number
          ends_at?: string
          exercise_id?: string | null
          id?: string
          is_active?: boolean
          set_number?: number | null
          started_at?: string
          timer_type?: Database["public"]["Enums"]["timer_type"]
          workout_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rest_timers_exercise_id_fkey"
            columns: ["exercise_id"]
            isOneToOne: false
            referencedRelation: "exercises"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rest_timers_workout_id_fkey"
            columns: ["workout_id"]
            isOneToOne: false
            referencedRelation: "workouts"
            referencedColumns: ["id"]
          },
        ]
      }
      routine_sessions: {
        Row: {
          created_at: string
          id: string
          order_index: number
          routine_id: string
          session_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          order_index: number
          routine_id: string
          session_id: string
        }
        Update: {
          created_at?: string
          id?: string
          order_index?: number
          routine_id?: string
          session_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "routine_sessions_routine_id_fkey"
            columns: ["routine_id"]
            isOneToOne: false
            referencedRelation: "routines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "routine_sessions_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      routines: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          is_public: boolean
          name: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_public?: boolean
          name: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          is_public?: boolean
          name?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "routines_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      session_exercises: {
        Row: {
          created_at: string
          exercise_id: string
          id: string
          notes: string | null
          order_index: number
          rest_between_sets_seconds: number
          session_id: string
          target_reps: number | null
          target_sets: number | null
          target_weight: number | null
        }
        Insert: {
          created_at?: string
          exercise_id: string
          id?: string
          notes?: string | null
          order_index: number
          rest_between_sets_seconds?: number
          session_id: string
          target_reps?: number | null
          target_sets?: number | null
          target_weight?: number | null
        }
        Update: {
          created_at?: string
          exercise_id?: string
          id?: string
          notes?: string | null
          order_index?: number
          rest_between_sets_seconds?: number
          session_id?: string
          target_reps?: number | null
          target_sets?: number | null
          target_weight?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "session_exercises_exercise_id_fkey"
            columns: ["exercise_id"]
            isOneToOne: false
            referencedRelation: "exercises"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "session_exercises_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "sessions"
            referencedColumns: ["id"]
          },
        ]
      }
      sessions: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_public: boolean
          name: string
          rest_between_exercises_seconds: number
          updated_at: string
          user_id: string | null
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_public?: boolean
          name: string
          rest_between_exercises_seconds?: number
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_public?: boolean
          name?: string
          rest_between_exercises_seconds?: number
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "sessions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          created_at: string
          email: string
          id: string
          timer_trigger_mode: Database["public"]["Enums"]["timer_trigger_mode"]
          updated_at: string
          weight_unit: Database["public"]["Enums"]["weight_unit"]
        }
        Insert: {
          created_at?: string
          email: string
          id: string
          timer_trigger_mode?: Database["public"]["Enums"]["timer_trigger_mode"]
          updated_at?: string
          weight_unit?: Database["public"]["Enums"]["weight_unit"]
        }
        Update: {
          created_at?: string
          email?: string
          id?: string
          timer_trigger_mode?: Database["public"]["Enums"]["timer_trigger_mode"]
          updated_at?: string
          weight_unit?: Database["public"]["Enums"]["weight_unit"]
        }
        Relationships: []
      }
      workout_exercises: {
        Row: {
          created_at: string
          exercise_id: string
          id: string
          notes: string | null
          order_index: number
          session_exercise_id: string | null
          status: Database["public"]["Enums"]["workout_exercise_status"]
          workout_id: string
        }
        Insert: {
          created_at?: string
          exercise_id: string
          id?: string
          notes?: string | null
          order_index: number
          session_exercise_id?: string | null
          status?: Database["public"]["Enums"]["workout_exercise_status"]
          workout_id: string
        }
        Update: {
          created_at?: string
          exercise_id?: string
          id?: string
          notes?: string | null
          order_index?: number
          session_exercise_id?: string | null
          status?: Database["public"]["Enums"]["workout_exercise_status"]
          workout_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workout_exercises_exercise_id_fkey"
            columns: ["exercise_id"]
            isOneToOne: false
            referencedRelation: "exercises"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workout_exercises_session_exercise_id_fkey"
            columns: ["session_exercise_id"]
            isOneToOne: false
            referencedRelation: "session_exercises"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workout_exercises_workout_id_fkey"
            columns: ["workout_id"]
            isOneToOne: false
            referencedRelation: "workouts"
            referencedColumns: ["id"]
          },
        ]
      }
      workouts: {
        Row: {
          completed_at: string | null
          created_at: string
          duration_seconds: number | null
          id: string
          name: string
          notes: string | null
          session_id: string | null
          started_at: string
          status: Database["public"]["Enums"]["workout_status"]
          user_id: string
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          duration_seconds?: number | null
          id?: string
          name: string
          notes?: string | null
          session_id?: string | null
          started_at?: string
          status?: Database["public"]["Enums"]["workout_status"]
          user_id: string
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          duration_seconds?: number | null
          id?: string
          name?: string
          notes?: string | null
          session_id?: string | null
          started_at?: string
          status?: Database["public"]["Enums"]["workout_status"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "workouts_session_id_fkey"
            columns: ["session_id"]
            isOneToOne: false
            referencedRelation: "sessions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "workouts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      mv_user_weekly_volume: {
        Row: {
          total_duration_seconds: number | null
          total_sets: number | null
          total_volume_kg: number | null
          total_workouts: number | null
          user_id: string | null
          week_start: string | null
        }
        Relationships: [
          {
            foreignKeyName: "workouts_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      clone_plan: {
        Args: { p_new_name: string; p_plan_id: string }
        Returns: string
      }
      clone_routine: {
        Args: { p_new_name: string; p_routine_id: string }
        Returns: string
      }
      clone_session: {
        Args: { p_new_name: string; p_session_id: string }
        Returns: string
      }
      get_exercise_alternatives: {
        Args: { p_exercise_id: string; p_limit?: number; p_user_id: string }
        Returns: {
          category: Database["public"]["Enums"]["exercise_category"]
          id: string
          is_public: boolean
          muscle_groups: string[]
          name: string
          user_id: string
        }[]
      }
      refresh_mv_weekly_volume: { Args: never; Returns: undefined }
      reorder_items: {
        Args: {
          p_items: Json
          p_parent_col: string
          p_parent_id: string
          p_table: string
        }
        Returns: undefined
      }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
    }
    Enums: {
      exercise_category: "Push" | "Pull" | "Legs" | "Core" | "Cardio" | "Other"
      pr_record_type: "max_weight" | "max_reps" | "max_volume"
      timer_trigger_mode: "auto" | "manual"
      timer_type: "between_sets" | "between_exercises"
      video_source: "youtube" | "storage"
      weight_unit: "kg" | "lb"
      workout_exercise_status:
        | "pending"
        | "in_progress"
        | "completed"
        | "skipped"
      workout_status: "active" | "paused" | "completed" | "cancelled"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      exercise_category: ["Push", "Pull", "Legs", "Core", "Cardio", "Other"],
      pr_record_type: ["max_weight", "max_reps", "max_volume"],
      timer_trigger_mode: ["auto", "manual"],
      timer_type: ["between_sets", "between_exercises"],
      video_source: ["youtube", "storage"],
      weight_unit: ["kg", "lb"],
      workout_exercise_status: [
        "pending",
        "in_progress",
        "completed",
        "skipped",
      ],
      workout_status: ["active", "paused", "completed", "cancelled"],
    },
  },
} as const
