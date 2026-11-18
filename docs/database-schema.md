# Database schema

The Supabase schema stores the [training data format](training-data-format.md) (version 1.0). This page lists the tables and maps every format field to a column, so the app's data model can be checked against both.

- **Migrations:** `supabase/migrations/20261117050645_drop_legacy_schema.sql` removes the previous workout schema; `20261117050646_training_data_schema.sql` creates this one.
- **Tests:** `supabase/tests/` (pgTAP), run with `supabase test db`.

## Tables

| Table                    | Holds                                        | Owner                                            |
| ------------------------ | -------------------------------------------- | ------------------------------------------------ |
| `users`                  | Profile and preferences, one row per account | `id` = `auth.uid()`                              |
| `exercises`              | Format `exercise`                            | `user_id`; `NULL` = curated catalogue, read-only |
| `exercise_muscle_groups` | `exercise.muscleGroups[]`                    | Through its exercise                             |
| `routines`               | Format `routine`                             | `user_id`                                        |
| `routine_items`          | `routine.items[]`                            | `user_id`                                        |
| `sessions`               | Format `session`                             | `user_id`                                        |
| `entries`                | `session.entries[]`                          | `user_id`                                        |
| `sets`                   | `entry.sets[]`                               | `user_id`                                        |
| `exercise_settings`      | User settings per exercise, outside format   | `user_id` (defaults to the caller)               |

### Access

- Every table has row level security. A signed-in user reads and writes only their own rows; catalogue exercises and their muscle groups are readable by everyone signed in and writable only with the service role.
- Child rows reference their parent through `(parent_id, user_id)`, so they cannot point at another user's routine, session or entry. Routine items, entries and exercise settings may only name exercises the user can read.
- Deleting an account (`auth.users`) removes all of its rows. An exercise that a routine or session uses cannot be deleted on its own; deleting a routine keeps the sessions started from it and clears their `routine_id`.
- `anon` has no table privileges. `authenticated` and `service_role` have `SELECT`, `INSERT`, `UPDATE` and `DELETE`.

## Keys and imports

- **Primary keys are the database's own.** Every `id` is a meaningless UUID. The app supplies its own UUID on insert; rows created on the server get `gen_random_uuid()` (version 4). Postgres 17 has no built-in UUID version 7, and a random key is enough at this scale; Postgres 18 adds `uuidv7()`. Bundle `id` values are never used as keys and need not be derived.
- **Upsert key.** An imported routine, session, entry or set is matched by its `externalRef`: `UNIQUE (user_id, external_provider, external_id)` on each table. Two users importing the same source item get two rows with different keys.
- **Curated catalogue.** Exercises with `user_id` NULL are a curated catalogue: readable by everyone signed in and written only with the service role. A catalogue row never carries an `externalRef` (CHECK `exercises_catalogue_has_no_external_ref`), so nothing a provider sends can create or change one.
- **Imported exercises are private.** An exercise from a provider is always a row of the importing user, matched by `UNIQUE (user_id, external_provider, external_id)` like every other imported item. Two users importing the same provider exercise get one private row each. The database does not enforce one exercise per movement per user, nor matching exercises without an `externalRef` by name and type: the importer and the app do.
- **Conflicts.** An insert that reuses another user's key fails with 23505. That tells the caller the key exists and nothing about the row. Keys are random, so they can only be learnt if they leak.

## Format field → column

Bundle-level fields (`formatVersion`, `generatedAt`, `source`, `locale`) describe an exchange file and are not stored.

Every `externalRef` is stored as two columns, `external_provider` and `external_id`, which are both set or both empty. An `order` is stored as `position`.

### Exercise

| Format field                      | Column                                                                           |
| --------------------------------- | -------------------------------------------------------------------------------- |
| `id`                              | `exercises.id`                                                                   |
| `externalRef.provider` / `.id`    | `exercises.external_provider` / `exercises.external_id`                          |
| `name`                            | `exercises.name`                                                                 |
| `type`                            | `exercises.type` (`exercise_type`)                                               |
| `equipment`                       | `exercises.equipment` (`equipment`)                                              |
| `muscleGroups[].muscle` / `.role` | `exercise_muscle_groups.muscle` / `.role`, one row each, linked by `exercise_id` |
| `instructions.setup`              | `exercises.setup_steps` (`text[]`)                                               |
| `instructions.execution`          | `exercises.execution_steps` (`text[]`)                                           |
| `instructions.tips`               | `exercises.tips` (`text[]`)                                                      |
| `media.image.uri`                 | `exercises.image_uri`                                                            |
| `media.video.uri`                 | `exercises.video_uri`                                                            |

### Routine

| Format field                           | Column                                                             |
| -------------------------------------- | ------------------------------------------------------------------ |
| `id`                                   | `routines.id`                                                      |
| `externalRef`                          | `routines.external_provider` / `routines.external_id`              |
| `name`                                 | `routines.name`                                                    |
| `description`                          | `routines.description`                                             |
| `items[]`                              | `routine_items`, linked by `routine_id`                            |
| `items[].order`                        | `routine_items.position`                                           |
| `items[].exerciseId`                   | `routine_items.exercise_id`                                        |
| `items[].targetSets`                   | `routine_items.target_sets`                                        |
| `items[].targetReps.min` / `.max`      | `routine_items.target_reps_min` / `routine_items.target_reps_max`  |
| `items[].targetWeight.value` / `.unit` | `routine_items.target_weight` / `routine_items.target_weight_unit` |
| `items[].targetDurationSeconds`        | `routine_items.target_duration_seconds`                            |
| `items[].restSeconds`                  | `routine_items.rest_seconds`                                       |
| `items[].notes`                        | `routine_items.notes`                                              |

A routine item has no `id` in the format; `routine_items.id` exists for sync only.

### Session

| Format field      | Column                                                |
| ----------------- | ----------------------------------------------------- |
| `id`              | `sessions.id`                                         |
| `externalRef`     | `sessions.external_provider` / `sessions.external_id` |
| `completedAt`     | `sessions.completed_at`                               |
| `timeZone`        | `sessions.time_zone`                                  |
| `startedAt`       | `sessions.started_at`                                 |
| `durationSeconds` | `sessions.duration_seconds`                           |
| `routineId`       | `sessions.routine_id`                                 |
| `name`            | `sessions.name`                                       |
| `notes`           | `sessions.notes`                                      |
| `entries[]`       | `entries`, linked by `session_id`                     |

### Entry

| Format field               | Column                                              |
| -------------------------- | --------------------------------------------------- |
| `id`                       | `entries.id`                                        |
| `externalRef`              | `entries.external_provider` / `entries.external_id` |
| `exerciseId`               | `entries.exercise_id`                               |
| `order`                    | `entries.position`                                  |
| `status`                   | `entries.status` (`entry_status`)                   |
| `replacedExerciseId`       | `entries.replaced_exercise_id`                      |
| `completedAt`              | `entries.completed_at`                              |
| `notes`                    | `entries.notes`                                     |
| `reconciliation.keep`      | `entries.reconciliation_keep` (`set_source`)        |
| `reconciliation.decidedBy` | `entries.reconciliation_decided_by`                 |
| `reconciliation.decidedAt` | `entries.reconciliation_decided_at`                 |
| `sets[]`                   | `sets`, linked by `entry_id`                        |

### Set

| Format field             | Column                                          |
| ------------------------ | ----------------------------------------------- |
| `id`                     | `sets.id`                                       |
| `order`                  | `sets.position`                                 |
| `source`                 | `sets.source` (`set_source`)                    |
| `externalRef`            | `sets.external_provider` / `sets.external_id`   |
| `reps`                   | `sets.reps`                                     |
| `durationSeconds`        | `sets.duration_seconds`                         |
| `distanceMeters`         | `sets.distance_meters`                          |
| `weight.value` / `.unit` | `sets.weight` / `sets.weight_unit`              |
| `rir`                    | `sets.rir`                                      |
| `restSeconds`            | `sets.rest_seconds`                             |
| `completedAt`            | `sets.completed_at`                             |
| `superseded`             | `sets.superseded` (never null, default `false`) |
| `warmup`                 | `sets.warmup` (never null, default `false`)     |

### Columns outside the format

| Column                                          | Purpose                                               |
| ----------------------------------------------- | ----------------------------------------------------- |
| `user_id` on every owned table                  | Owner, used by row level security                     |
| `created_at`, `updated_at` on every table       | Audit; the app pulls changes by `updated_at`          |
| `exercise_muscle_groups.id`, `routine_items.id` | Row identity for sync                                 |
| `users.*`                                       | Profile: `email`, `weight_unit`, `timer_trigger_mode` |

## User settings

`exercise_settings` holds a user's settings for one exercise, catalogue or their own. It is a user setting, not part of the training data format, so it is never exported or imported.

| Column         | Meaning                                                                      |
| -------------- | ---------------------------------------------------------------------------- |
| `user_id`      | Owner; defaults to the caller                                                |
| `exercise_id`  | The exercise; deleting it deletes its settings                               |
| `rest_enabled` | Rest timer between sets of this exercise is on (default `true`)              |
| `rest_seconds` | Rest between sets, 0–3600 seconds (default 90); kept when rest is turned off |

The key is `(user_id, exercise_id)`, which is also the upsert key: saving a setting again updates it. The setting applies in every session that uses the exercise. The running timer lives on the device; the database stores no timer.

## Rules enforced by the database

| Format rule                               | Enforcement                                                                                                                                             |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `unique-external-ref`                     | `UNIQUE (user_id, external_provider, external_id)` per table; catalogue exercises never carry an `externalRef`                                          |
| `order`                                   | `UNIQUE (routine_id, position)`, `UNIQUE (session_id, position)`, `UNIQUE (entry_id, source, position)`, checked at statement end; positions start at 1 |
| `one-entry-per-exercise`                  | Unique index on `entries (session_id, user_id, exercise_id)` where `status = 'done'` (`user_id` follows from the session)                               |
| Imported sets carry the key               | `sets.source = 'imported'` requires `external_id`                                                                                                       |
| `reconciliation` (row part)               | `keep` and `decidedBy` both or neither; `decidedAt` needs them; `default` keeps `imported`                                                              |
| `exercise-type`                           | Trigger: cardio sets have a duration and no reps or weight; only cardio sets have a distance                                                            |
| Skipped entries                           | Trigger: a skipped entry has no sets                                                                                                                    |
| `range`                                   | `startedAt ≤ completedAt`, duration fits the session, `min ≤ max`, no entry completes after its session (triggers on both sides)                        |
| Text bounds                               | Exercise names are not blank and at most 200 characters; every `external_id` is 1–200 characters                                                        |
| Set fields                                | Reps or duration; distance needs duration; weight needs its unit; `rir` 0–10                                                                            |
| `exercise-reference`, `routine-reference` | Foreign keys                                                                                                                                            |

### Left to the app

- A `done` entry has at least one set, and a routine or session has at least one item or entry. Rows are written one at a time, so these hold only once a whole session is stored.
- `reconciliation` is present exactly when an entry mixes sources, and `superseded` marks the source that was not kept. Imported sets can arrive before the app reconciles, so a mixed entry without a decision is a valid state in the database.
- Changing an exercise's own `type` after sets exist is not re-checked. Switching an entry to another exercise is: its sets must fit the new type.
