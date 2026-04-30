# @tnw/database

Shared database package for tnw-tracker. Provides:

- **`types.gen.ts`** — Auto-generated Supabase types
- **`src/seed.ts`** — Seed script for local development data

## Seed Script

Populates the local Supabase dev instance with realistic data for designing
screens and flows:

- 2 test users (dev + secondary)
- Template sessions, routines, and an 8-week training plan
- 10 completed workouts with exercise sets and weight progression

### Prerequisites

- Local Supabase running (`supabase start`)
- Migrations applied (`supabase db reset` — also runs `seed.sql` for global exercises)
- `SUPABASE_SERVICE_ROLE_KEY` set in your environment

### Running

```bash
# From the monorepo root
pnpm --filter @tnw/database run seed

# Or directly
cd packages/database
npx tsx src/seed.ts
```

### Environment Variables

| Variable                    | Required | Default                  | Description                                                       |
| --------------------------- | -------- | ------------------------ | ----------------------------------------------------------------- |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes      | —                        | Service role key from Supabase dashboard (Project Settings → API) |
| `SUPABASE_URL`              | No       | `http://127.0.0.1:54321` | Supabase local API URL                                            |

### Test Credentials

| User      | Email                   | Password |
| --------- | ----------------------- | -------- |
| Dev       | dev@tnw-tracker.local   | Dev1234! |
| Secondary | user2@tnw-tracker.local | Dev1234! |

### Idempotency

The script is idempotent — it uses `upsert` for parent entities and deletes +
re-inserts child records (session_exercises, routine_sessions, plan_routines,
workout_exercises, exercise_sets). Safe to run multiple times.

### Order

1. `supabase db reset` runs migrations then `supabase/seed.sql` (global exercises + quotes)
2. `pnpm --filter @tnw/database run seed` creates users + templates + workout history
