/**
 * Seed script for local development — user-specific data.
 *
 * Runs AFTER `supabase db reset` has applied migrations and seed.sql.
 * Must be run manually with:
 *   npx tsx packages/database/src/seed.ts
 *
 * Prerequisites:
 *   SUPABASE_SERVICE_ROLE_KEY in environment
 *   Supabase local dev running (`supabase start`)
 */

import { createClient } from "@supabase/supabase-js";

// ── Config ───────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321"; // local dev default
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  console.error("❌ SUPABASE_SERVICE_ROLE_KEY is required. Set it in your environment.");
  process.exit(1);
}

// Service-role client — bypasses RLS, can access auth.admin
const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// ── User IDs — resolved at runtime after auth.admin.createUser ───────────────

let DEV_USER_ID = "";
let SECONDARY_USER_ID = "";

// Exercise UUIDs — match seed.sql
const EXERCISES = {
  bench_press: "e1000001-0000-0000-0000-000000000001",
  db_shoulder_press: "e1000002-0000-0000-0000-000000000002",
  incline_db_press: "e1000003-0000-0000-0000-000000000003",
  tricep_pushdown: "e1000004-0000-0000-0000-000000000004",
  lateral_raises: "e1000005-0000-0000-0000-000000000005",
  overhead_tricep_ext: "e1000006-0000-0000-0000-000000000006",
  barbell_row: "e1000007-0000-0000-0000-000000000007",
  pull_up: "e1000008-0000-0000-0000-000000000008",
  lat_pulldown: "e1000009-0000-0000-0000-000000000009",
  seated_cable_row: "e100000a-0000-0000-0000-00000000000a",
  face_pull: "e100000b-0000-0000-0000-00000000000b",
  back_squat: "e100000c-0000-0000-0000-00000000000c",
  rdl: "e100000d-0000-0000-0000-00000000000d",
  leg_press: "e100000e-0000-0000-0000-00000000000e",
  walking_lunge: "e100000f-0000-0000-0000-00000000000f",
  leg_curl: "e1000010-0000-0000-0000-000000000010",
  plank: "e1000011-0000-0000-0000-000000000011",
  hanging_leg_raise: "e1000012-0000-0000-0000-000000000012",
  cable_crunch: "e1000013-0000-0000-0000-000000000013",
} as const;

// ── Date helpers ─────────────────────────────────────────────────────────────

const MS_PER_DAY = 86_400_000;

function daysAgo(days: number): Date {
  return new Date(Date.now() - days * MS_PER_DAY);
}

function toISO(d: Date): string {
  return d.toISOString();
}

// ── Sleep helper for rate limiting ───────────────────────────────────────────

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log("🌱 Seeding dev environment…\n");

  // ─── 1. Create users ────────────────────────────────────────────────────
  await createUsers();
  if (!DEV_USER_ID) {
    console.error("❌ DEV_USER_ID not resolved — aborting.");
    process.exit(1);
  }

  // ─── 2. Create template sessions + exercises ─────────────────────────────
  const sessionIds = await createSessions();

  // ─── 3. Create routines + routine_sessions ───────────────────────────────
  const routineIds = await createRoutines(sessionIds);

  // ─── 4. Create plan + plan_routines ──────────────────────────────────────
  await createPlan(routineIds);

  // ─── 5. Create historical workouts ───────────────────────────────────────
  await createWorkouts(sessionIds);

  console.log("\n✅ Seed completed successfully!");
}

// ── 1. Users ─────────────────────────────────────────────────────────────────

async function createUsers() {
  console.log("→ Creating users…");

  // ── Helper: create or fetch existing user ───────────────────────────────
  async function upsertUser(email: string, password: string): Promise<string> {
    const { data, error } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {},
    });
    if (error) {
      if (error.message.includes("already been registered")) {
        // Fetch the existing user ID
        const { data: list } = await supabase.auth.admin.listUsers();
        const existing = list?.users.find((u) => u.email === email);
        if (existing) return existing.id;
      }
      console.error(`  ❌ Failed to create ${email}:`, error.message);
      return "";
    }
    return data.user?.id ?? "";
  }

  DEV_USER_ID = await upsertUser("dev@tnw-tracker.local", "Dev1234!");
  if (DEV_USER_ID) console.log(`  ✅ dev@tnw-tracker.local (Dev1234!) — ${DEV_USER_ID}`);

  SECONDARY_USER_ID = await upsertUser("user2@tnw-tracker.local", "Dev1234!");
  if (SECONDARY_USER_ID)
    console.log(`  ✅ user2@tnw-tracker.local (Dev1234!) — ${SECONDARY_USER_ID}`);

  // Wait a beat so the auth trigger fires and creates public.users rows
  await sleep(1000);
}

// ── 2. Sessions ──────────────────────────────────────────────────────────────

interface SessionDef {
  id: string;
  name: string;
  description: string;
  restBtwEx: number; // seconds
  exercises: {
    exerciseId: string;
    targetSets: number;
    targetReps: number;
    targetWeight: number;
    restBtwSets: number;
    notes?: string;
  }[];
}

async function createSessions(): Promise<Record<string, string>> {
  console.log("→ Creating sessions…");

  const PUSH_ID = "b1000001-0000-0000-0000-000000000001";
  const PULL_ID = "b1000002-0000-0000-0000-000000000002";
  const LEGS_ID = "b1000003-0000-0000-0000-000000000003";
  const UPPER_ID = "b1000004-0000-0000-0000-000000000004";
  const LOWER_ID = "b1000005-0000-0000-0000-000000000005";

  const sessions: SessionDef[] = [
    {
      id: PUSH_ID,
      name: "Upper Push",
      description: "Chest, shoulders, and triceps — heavy pressing + isolation finishers",
      restBtwEx: 120,
      exercises: [
        {
          exerciseId: EXERCISES.bench_press,
          targetSets: 4,
          targetReps: 8,
          targetWeight: 80,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.db_shoulder_press,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 30,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.incline_db_press,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 32,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.lateral_raises,
          targetSets: 4,
          targetReps: 15,
          targetWeight: 10,
          restBtwSets: 60,
        },
        {
          exerciseId: EXERCISES.tricep_pushdown,
          targetSets: 3,
          targetReps: 12,
          targetWeight: 25,
          restBtwSets: 60,
        },
        {
          exerciseId: EXERCISES.overhead_tricep_ext,
          targetSets: 3,
          targetReps: 12,
          targetWeight: 12,
          restBtwSets: 60,
          notes: "Use rope attachment",
        },
      ],
    },
    {
      id: PULL_ID,
      name: "Pull Day",
      description: "Back thickness and width — vertical + horizontal pulling, rear delts",
      restBtwEx: 120,
      exercises: [
        {
          exerciseId: EXERCISES.pull_up,
          targetSets: 4,
          targetReps: 8,
          targetWeight: 0,
          restBtwSets: 120,
          notes: "Add weight if 8 reps achieved",
        },
        {
          exerciseId: EXERCISES.barbell_row,
          targetSets: 4,
          targetReps: 8,
          targetWeight: 70,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.lat_pulldown,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 55,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.seated_cable_row,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 50,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.face_pull,
          targetSets: 3,
          targetReps: 15,
          targetWeight: 12,
          restBtwSets: 60,
          notes: "Focus on external rotation, not weight",
        },
      ],
    },
    {
      id: LEGS_ID,
      name: "Legs Day",
      description: "Heavy squats, posterior chain, and core finisher",
      restBtwEx: 150,
      exercises: [
        {
          exerciseId: EXERCISES.back_squat,
          targetSets: 4,
          targetReps: 6,
          targetWeight: 100,
          restBtwSets: 180,
        },
        {
          exerciseId: EXERCISES.rdl,
          targetSets: 3,
          targetReps: 8,
          targetWeight: 80,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.leg_press,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 140,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.walking_lunge,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 20,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.leg_curl,
          targetSets: 3,
          targetReps: 12,
          targetWeight: 35,
          restBtwSets: 60,
        },
        {
          exerciseId: EXERCISES.plank,
          targetSets: 3,
          targetReps: 1,
          targetWeight: 0,
          restBtwSets: 60,
          notes: "Hold 45-60s per set",
        },
      ],
    },
    {
      id: UPPER_ID,
      name: "Upper Body",
      description: "Combined push/pull — efficiency-focused full upper workout",
      restBtwEx: 90,
      exercises: [
        {
          exerciseId: EXERCISES.bench_press,
          targetSets: 3,
          targetReps: 8,
          targetWeight: 80,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.pull_up,
          targetSets: 3,
          targetReps: 8,
          targetWeight: 0,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.db_shoulder_press,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 30,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.seated_cable_row,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 50,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.lateral_raises,
          targetSets: 3,
          targetReps: 15,
          targetWeight: 10,
          restBtwSets: 60,
        },
        {
          exerciseId: EXERCISES.face_pull,
          targetSets: 3,
          targetReps: 15,
          targetWeight: 12,
          restBtwSets: 60,
        },
      ],
    },
    {
      id: LOWER_ID,
      name: "Lower Body",
      description: "Quad-dominant + posterior chain — legs and abs",
      restBtwEx: 150,
      exercises: [
        {
          exerciseId: EXERCISES.back_squat,
          targetSets: 4,
          targetReps: 6,
          targetWeight: 100,
          restBtwSets: 180,
        },
        {
          exerciseId: EXERCISES.rdl,
          targetSets: 3,
          targetReps: 8,
          targetWeight: 80,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.leg_press,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 140,
          restBtwSets: 120,
        },
        {
          exerciseId: EXERCISES.walking_lunge,
          targetSets: 3,
          targetReps: 10,
          targetWeight: 20,
          restBtwSets: 90,
        },
        {
          exerciseId: EXERCISES.leg_curl,
          targetSets: 3,
          targetReps: 12,
          targetWeight: 35,
          restBtwSets: 60,
        },
        {
          exerciseId: EXERCISES.hanging_leg_raise,
          targetSets: 3,
          targetReps: 12,
          targetWeight: 0,
          restBtwSets: 60,
        },
      ],
    },
  ];

  for (const s of sessions) {
    const { error: sessErr } = await supabase.from("sessions").upsert({
      id: s.id,
      user_id: DEV_USER_ID,
      name: s.name,
      description: s.description,
      rest_between_exercises_seconds: s.restBtwEx,
    });
    if (sessErr) {
      console.error(`  ❌ Session "${s.name}":`, sessErr.message);
      continue;
    }

    // Delete existing session_exercises for idempotent re-seed
    await supabase.from("session_exercises").delete().eq("session_id", s.id);

    const sessionExercises = s.exercises.map((ex, idx) => ({
      session_id: s.id,
      exercise_id: ex.exerciseId,
      order_index: idx + 1,
      target_sets: ex.targetSets,
      target_reps: ex.targetReps,
      target_weight: ex.targetWeight,
      rest_between_sets_seconds: ex.restBtwSets,
      notes: ex.notes ?? null,
    }));

    const { error: seErr } = await supabase.from("session_exercises").insert(sessionExercises);
    if (seErr) {
      console.error(`  ❌ Session exercises "${s.name}":`, seErr.message);
    } else {
      console.log(`  ✅ ${s.name} (${s.exercises.length} exercises)`);
    }
  }

  return {
    push: PUSH_ID,
    pull: PULL_ID,
    legs: LEGS_ID,
    upper: UPPER_ID,
    lower: LOWER_ID,
  };
}

// ── 3. Routines ──────────────────────────────────────────────────────────────

async function createRoutines(sessions: Record<string, string>): Promise<Record<string, string>> {
  console.log("→ Creating routines…");

  const PPL_ID = "d1000001-0000-0000-0000-000000000001";
  const UL_ID = "d1000002-0000-0000-0000-000000000002";

  const routines = [
    {
      id: PPL_ID,
      name: "Push-Pull-Legs",
      description: "Classic 3-day split: push, pull, legs. Rotates 2x per week in the 8-week plan.",
      sessionIds: [sessions.push, sessions.pull, sessions.legs],
    },
    {
      id: UL_ID,
      name: "Upper-Lower Split",
      description:
        "4-day split alternating upper and lower. Great for frequency and volume distribution.",
      sessionIds: [sessions.upper, sessions.lower],
    },
  ];

  for (const r of routines) {
    // Upsert routine
    const { error: rErr } = await supabase.from("routines").upsert({
      id: r.id,
      user_id: DEV_USER_ID,
      name: r.name,
      description: r.description,
      is_active: true,
    });
    if (rErr) {
      console.error(`  ❌ Routine "${r.name}":`, rErr.message);
      continue;
    }

    // Delete existing routine_sessions for idempotent re-seed
    await supabase.from("routine_sessions").delete().eq("routine_id", r.id);

    const routineSessions = r.sessionIds.map((sid, idx) => ({
      routine_id: r.id,
      session_id: sid,
      order_index: idx + 1,
    }));

    const { error: rsErr } = await supabase.from("routine_sessions").insert(routineSessions);
    if (rsErr) {
      console.error(`  ❌ Routine sessions "${r.name}":`, rsErr.message);
    } else {
      console.log(`  ✅ ${r.name} (${r.sessionIds.length} sessions)`);
    }
  }

  return { ppl: PPL_ID, ul: UL_ID };
}

// ── 4. Plan ──────────────────────────────────────────────────────────────────

async function createPlan(routines: Record<string, string>) {
  console.log("→ Creating plan…");

  const PLAN_ID = "f1000001-0000-0000-0000-000000000001";

  // Upsert plan
  const { error: pErr } = await supabase.from("plans").upsert({
    id: PLAN_ID,
    user_id: DEV_USER_ID,
    name: "8-Week Strength Foundation",
    description:
      "Progressive overload program alternating PPL and Upper-Lower splits. Designed for intermediate lifters building strength and muscle mass.",
    duration_weeks: 8,
    is_active: true,
  });
  if (pErr) {
    console.error(`  ❌ Plan:`, pErr.message);
    return;
  }

  // Delete existing plan_routines for idempotent re-seed
  await supabase.from("plan_routines").delete().eq("plan_id", PLAN_ID);

  // 8-week schedule: alternate PPL (weeks 1,3,5,7) and UL (weeks 2,4,6,8)
  const schedule = [
    { week: 1, routineId: routines.ppl },
    { week: 2, routineId: routines.ul },
    { week: 3, routineId: routines.ppl },
    { week: 4, routineId: routines.ul },
    { week: 5, routineId: routines.ppl },
    { week: 6, routineId: routines.ul },
    { week: 7, routineId: routines.ppl },
    { week: 8, routineId: routines.ul },
  ];

  const planRoutines = schedule.map((s) => ({
    plan_id: PLAN_ID,
    routine_id: s.routineId,
    order_index: s.week,
  }));

  const { error: prErr } = await supabase.from("plan_routines").insert(planRoutines);
  if (prErr) {
    console.error(`  ❌ Plan routines:`, prErr.message);
  } else {
    console.log(`  ✅ 8-Week Strength Foundation (${schedule.length} weeks)`);
  }
}

// ── 5. Workouts ──────────────────────────────────────────────────────────────

interface WorkoutDef {
  id: string;
  name: string;
  sessionId: string;
  daysAgo: number;
  durationSec: number;
  notes?: string;
  // exerciseId → weight progression across sets [warmup, working1, working2, working3, backoff?]
  weightProgression: Record<
    string,
    { reps: number[]; weight: number[]; rpe?: number[]; notes?: string }
  >;
}

async function createWorkouts(sessions: Record<string, string>) {
  console.log("→ Creating workout history…");

  // ── Weight progression strategy (intermediate lifter) ───────────────────
  // We simulate a 2.5-5% weekly increase. Base weights increase each cycle.
  // Base: week -6/-5 → target weights from session templates
  // Cycle 2 (week -4/-3): +3% on compound lifts
  // Cycle 3 (week -2/-1): +3% more on compound lifts

  const workouts: WorkoutDef[] = [
    // ── Week -6: PPL (starting weights) ───────────────────────────────────
    {
      id: "a0000001-0000-0000-0000-000000000001",
      name: "Upper Push",
      sessionId: sessions.push,
      daysAgo: 42,
      durationSec: 3780, // ~63min
      notes: "Felt strong. Bench moved well.",
      weightProgression: {
        [EXERCISES.bench_press]: {
          reps: [10, 8, 8, 7],
          weight: [60, 80, 80, 75],
          rpe: [5, 8, 8.5, 9],
        },
        [EXERCISES.db_shoulder_press]: { reps: [10, 10, 10], weight: [30, 30, 30], rpe: [7, 8, 9] },
        [EXERCISES.incline_db_press]: { reps: [10, 10, 9], weight: [32, 32, 32], rpe: [7, 8, 9] },
        [EXERCISES.lateral_raises]: {
          reps: [15, 15, 15, 12],
          weight: [10, 10, 10, 10],
          rpe: [6, 7, 8, 9],
        },
        [EXERCISES.tricep_pushdown]: { reps: [12, 12, 10], weight: [25, 25, 25], rpe: [7, 8, 9] },
        [EXERCISES.overhead_tricep_ext]: {
          reps: [12, 12, 10],
          weight: [12, 12, 12],
          rpe: [7, 8, 9],
        },
      },
    },
    {
      id: "a0000002-0000-0000-0000-000000000002",
      name: "Pull Day",
      sessionId: sessions.pull,
      daysAgo: 40,
      durationSec: 3600, // 60min
      notes: "Added 5kg to rows. Pull-ups still bodyweight.",
      weightProgression: {
        [EXERCISES.pull_up]: { reps: [8, 8, 7, 6], weight: [0, 0, 0, 0], rpe: [7, 8, 8.5, 9.5] },
        [EXERCISES.barbell_row]: {
          reps: [10, 8, 8, 8],
          weight: [60, 70, 70, 70],
          rpe: [5, 7, 8, 8.5],
        },
        [EXERCISES.lat_pulldown]: { reps: [10, 10, 9], weight: [55, 55, 55], rpe: [7, 8, 9] },
        [EXERCISES.seated_cable_row]: {
          reps: [10, 10, 10],
          weight: [50, 50, 50],
          rpe: [7, 8, 8.5],
        },
        [EXERCISES.face_pull]: { reps: [15, 15, 12], weight: [12, 12, 12], rpe: [6, 7, 8] },
      },
    },
    {
      id: "a0000003-0000-0000-0000-000000000003",
      name: "Legs Day",
      sessionId: sessions.legs,
      daysAgo: 38,
      durationSec: 4200, // 70min
      notes: "Heavy squats — depth was good. RPE 9 on last set.",
      weightProgression: {
        [EXERCISES.back_squat]: {
          reps: [8, 6, 6, 6],
          weight: [70, 100, 100, 100],
          rpe: [5, 7.5, 8.5, 9],
        },
        [EXERCISES.rdl]: { reps: [8, 8, 8], weight: [80, 80, 80], rpe: [7, 8, 8.5] },
        [EXERCISES.leg_press]: { reps: [12, 10, 10], weight: [120, 140, 140], rpe: [6, 7.5, 8] },
        [EXERCISES.walking_lunge]: { reps: [10, 10, 8], weight: [20, 20, 20], rpe: [7, 8, 8.5] },
        [EXERCISES.leg_curl]: { reps: [12, 12, 10], weight: [35, 35, 35], rpe: [7, 8, 9] },
        [EXERCISES.plank]: {
          reps: [1, 1, 1],
          weight: [0, 0, 0],
          rpe: [6, 7, 8],
          notes: "Hold 50-55-45s",
        },
      },
    },
    // ── Week -5: Upper-Lower ──────────────────────────────────────────────
    {
      id: "a0000004-0000-0000-0000-000000000004",
      name: "Upper Body",
      sessionId: sessions.upper,
      daysAgo: 34,
      durationSec: 3600,
      weightProgression: {
        [EXERCISES.bench_press]: { reps: [10, 8, 8], weight: [60, 80, 80], rpe: [5, 7.5, 8.5] },
        [EXERCISES.pull_up]: { reps: [8, 8, 7], weight: [0, 0, 0], rpe: [7, 8, 9] },
        [EXERCISES.db_shoulder_press]: { reps: [10, 10, 9], weight: [30, 30, 30], rpe: [7, 8, 9] },
        [EXERCISES.seated_cable_row]: { reps: [10, 10, 8], weight: [50, 50, 50], rpe: [7, 8, 9] },
        [EXERCISES.lateral_raises]: { reps: [15, 15, 12], weight: [10, 10, 10], rpe: [6, 7, 8] },
        [EXERCISES.face_pull]: { reps: [15, 15, 15], weight: [12, 12, 12], rpe: [6, 7, 7.5] },
      },
    },
    {
      id: "a0000005-0000-0000-0000-000000000005",
      name: "Lower Body",
      sessionId: sessions.lower,
      daysAgo: 32,
      durationSec: 3900,
      notes: "Squat depth improving. RDLs felt great.",
      weightProgression: {
        [EXERCISES.back_squat]: {
          reps: [8, 6, 6, 6],
          weight: [70, 100, 100, 100],
          rpe: [5, 7, 8, 8.5],
        },
        [EXERCISES.rdl]: { reps: [8, 8, 8], weight: [80, 80, 80], rpe: [7, 8, 8.5] },
        [EXERCISES.leg_press]: { reps: [12, 10, 10], weight: [120, 140, 140], rpe: [6, 7, 8] },
        [EXERCISES.walking_lunge]: { reps: [10, 10, 10], weight: [20, 20, 20], rpe: [7, 8, 8] },
        [EXERCISES.leg_curl]: { reps: [12, 12, 10], weight: [35, 35, 35], rpe: [7, 8, 9] },
        [EXERCISES.hanging_leg_raise]: { reps: [12, 12, 10], weight: [0, 0, 0], rpe: [7, 8, 9] },
      },
    },
    // ── Week -4: PPL (+3% on compounds) ───────────────────────────────────
    {
      id: "a0000006-0000-0000-0000-000000000006",
      name: "Upper Push",
      sessionId: sessions.push,
      daysAgo: 27,
      durationSec: 3900,
      notes: "Bench +2.5kg. Hit all reps! Progressing nicely.",
      weightProgression: {
        [EXERCISES.bench_press]: {
          reps: [8, 8, 8, 8],
          weight: [60, 82.5, 82.5, 82.5],
          rpe: [5, 7.5, 8, 8.5],
        },
        [EXERCISES.db_shoulder_press]: {
          reps: [10, 10, 10],
          weight: [32, 32, 32],
          rpe: [7, 8, 8.5],
        },
        [EXERCISES.incline_db_press]: { reps: [10, 10, 9], weight: [34, 34, 34], rpe: [7, 8, 9] },
        [EXERCISES.lateral_raises]: {
          reps: [15, 15, 15, 12],
          weight: [10, 10, 10, 10],
          rpe: [6, 7, 8, 9],
        },
        [EXERCISES.tricep_pushdown]: {
          reps: [12, 12, 10],
          weight: [27.5, 27.5, 27.5],
          rpe: [7, 8, 9],
        },
        [EXERCISES.overhead_tricep_ext]: {
          reps: [12, 12, 11],
          weight: [14, 14, 14],
          rpe: [7, 8, 8.5],
        },
      },
    },
    {
      id: "a0000007-0000-0000-0000-000000000007",
      name: "Pull Day",
      sessionId: sessions.pull,
      daysAgo: 25,
      durationSec: 3600,
      notes: "Pull-ups with 2.5kg weighted — first time! Rows +5kg.",
      weightProgression: {
        [EXERCISES.pull_up]: {
          reps: [8, 7, 7, 6],
          weight: [2.5, 2.5, 2.5, 0],
          rpe: [7, 8, 8.5, 9],
        },
        [EXERCISES.barbell_row]: {
          reps: [10, 8, 8, 8],
          weight: [60, 75, 75, 75],
          rpe: [5, 7, 8, 8],
        },
        [EXERCISES.lat_pulldown]: { reps: [10, 10, 9], weight: [57.5, 57.5, 57.5], rpe: [7, 8, 9] },
        [EXERCISES.seated_cable_row]: {
          reps: [10, 10, 10],
          weight: [52.5, 52.5, 52.5],
          rpe: [7, 8, 8.5],
        },
        [EXERCISES.face_pull]: { reps: [15, 15, 13], weight: [12, 12, 12], rpe: [6, 7, 8] },
      },
    },
    // ── Week -3: Upper Body ───────────────────────────────────────────────
    {
      id: "a0000008-0000-0000-0000-000000000008",
      name: "Upper Body",
      sessionId: sessions.upper,
      daysAgo: 20,
      durationSec: 3600,
      notes: "Cable rows +2.5kg. Bench moved fast.",
      weightProgression: {
        [EXERCISES.bench_press]: { reps: [8, 8, 8], weight: [60, 82.5, 82.5], rpe: [5, 7, 8] },
        [EXERCISES.pull_up]: { reps: [8, 7, 6], weight: [0, 0, 0], rpe: [7, 8, 9] },
        [EXERCISES.db_shoulder_press]: { reps: [10, 10, 9], weight: [32, 32, 32], rpe: [7, 8, 9] },
        [EXERCISES.seated_cable_row]: {
          reps: [10, 10, 10],
          weight: [52.5, 52.5, 52.5],
          rpe: [7, 8, 8],
        },
        [EXERCISES.lateral_raises]: { reps: [15, 15, 12], weight: [12, 12, 12], rpe: [6, 7, 8] },
        [EXERCISES.face_pull]: { reps: [15, 15, 15], weight: [14, 14, 14], rpe: [6, 7, 7.5] },
      },
    },
    // ── Week -2: Push + Pull (+3% more) ───────────────────────────────────
    {
      id: "a0000009-0000-0000-0000-000000000009",
      name: "Upper Push",
      sessionId: sessions.push,
      daysAgo: 13,
      durationSec: 3900,
      notes: "Bench 85kg! PR incoming soon. Everything moved well.",
      weightProgression: {
        [EXERCISES.bench_press]: {
          reps: [8, 8, 8, 7],
          weight: [60, 85, 85, 85],
          rpe: [5, 7.5, 8, 9],
        },
        [EXERCISES.db_shoulder_press]: { reps: [10, 10, 9], weight: [34, 34, 34], rpe: [7, 8, 9] },
        [EXERCISES.incline_db_press]: {
          reps: [10, 10, 10],
          weight: [34, 34, 34],
          rpe: [7, 7.5, 8.5],
        },
        [EXERCISES.lateral_raises]: {
          reps: [15, 15, 15, 15],
          weight: [10, 10, 10, 10],
          rpe: [6, 7, 7, 8],
        },
        [EXERCISES.tricep_pushdown]: {
          reps: [12, 12, 11],
          weight: [27.5, 27.5, 27.5],
          rpe: [7, 8, 8.5],
        },
        [EXERCISES.overhead_tricep_ext]: {
          reps: [12, 12, 12],
          weight: [14, 14, 14],
          rpe: [7, 7.5, 8],
        },
      },
    },
    // ── Week -1: Legs Day ─────────────────────────────────────────────────
    {
      id: "a0000010-0000-0000-0000-000000000010",
      name: "Legs Day",
      sessionId: sessions.legs,
      daysAgo: 6,
      durationSec: 4200,
      notes: "Squats at 105kg. RPE 9 on last set but depth was solid. Leg press +10kg.",
      weightProgression: {
        [EXERCISES.back_squat]: {
          reps: [8, 6, 6, 5],
          weight: [70, 105, 105, 105],
          rpe: [5, 7.5, 8.5, 9],
        },
        [EXERCISES.rdl]: { reps: [8, 8, 8], weight: [85, 85, 85], rpe: [7, 8, 9] },
        [EXERCISES.leg_press]: { reps: [12, 10, 10], weight: [130, 150, 150], rpe: [6, 7.5, 8.5] },
        [EXERCISES.walking_lunge]: { reps: [10, 10, 10], weight: [22, 22, 22], rpe: [7, 8, 8.5] },
        [EXERCISES.leg_curl]: { reps: [12, 12, 10], weight: [37.5, 37.5, 37.5], rpe: [7, 8, 9] },
        [EXERCISES.plank]: {
          reps: [1, 1, 1],
          weight: [0, 0, 0],
          rpe: [6, 7, 7],
          notes: "Hold 55-60-50s",
        },
      },
    },
  ];

  let created = 0;
  for (const w of workouts) {
    const startedAt = daysAgo(w.daysAgo);
    const completedAt = new Date(startedAt.getTime() + w.durationSec * 1000);

    // Upsert workout
    const { error: wErr } = await supabase.from("workouts").upsert({
      id: w.id,
      user_id: DEV_USER_ID,
      session_id: w.sessionId,
      name: w.name,
      status: "completed",
      started_at: toISO(startedAt),
      completed_at: toISO(completedAt),
      duration_seconds: w.durationSec,
      notes: w.notes ?? null,
    });
    if (wErr) {
      console.error(`  ❌ Workout "${w.name}" (${w.daysAgo}d ago):`, wErr.message);
      continue;
    }

    // Delete existing workout_exercises for idempotent re-seed
    await supabase.from("workout_exercises").delete().eq("workout_id", w.id);

    // Insert workout_exercises + exercise_sets
    let orderIdx = 0;
    for (const [exerciseId, prog] of Object.entries(w.weightProgression)) {
      orderIdx++;

      const { data: we, error: weErr } = await supabase
        .from("workout_exercises")
        .insert({
          workout_id: w.id,
          exercise_id: exerciseId,
          order_index: orderIdx,
          status: "completed",
        })
        .select("id")
        .single();

      if (weErr) {
        console.error(`  ❌ Workout exercise ${exerciseId}:`, weErr.message);
        continue;
      }

      // Insert sets
      const sets = prog.reps.map((reps, i) => ({
        workout_exercise_id: we.id,
        set_number: i + 1,
        reps,
        weight: prog.weight[i],
        weight_unit: "kg" as const,
        rpe: prog.rpe?.[i] != null ? Math.round(prog.rpe[i]) : null,
        is_warmup: i === 0 && prog.weight[0] < prog.weight[prog.weight.length - 1] * 0.8,
        completed_at: toISO(new Date(startedAt.getTime() + (orderIdx * 120 + i * 150) * 1000)),
      }));

      const { error: setErr } = await supabase.from("exercise_sets").insert(sets);
      if (setErr) {
        console.error(`  ❌ Sets for ${exerciseId}:`, setErr.message);
      }
    }

    created++;
    console.log(
      `  ✅ ${w.name} (${w.daysAgo}d ago, ${Object.keys(w.weightProgression).length} exercises)`
    );
  }

  console.log(`  🏋️  ${created} workouts created`);
}

// ── Run ──────────────────────────────────────────────────────────────────────

main().catch((err) => {
  console.error("\n❌ Seed failed:", err);
  process.exit(1);
});
