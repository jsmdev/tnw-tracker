# Database schema

The Supabase schema stores the [training data format](training-data-format.md) (version 1.0). This page lists the tables and maps every format field to a column, so the app's data model can be checked against both.

- **Migrations:** `supabase/migrations/20261117050645_drop_legacy_schema.sql` removes the previous workout schema; `20261117050646_training_data_schema.sql` creates this one. `20261119120000_sync_tombstones.sql` and `20261119130000_sync_template_children.sql` add what the sync needs (tombstones, muscle-group order).
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

| Format field                      | Column                                                                                                                         |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `id`                              | `exercises.id`                                                                                                                 |
| `externalRef.provider` / `.id`    | `exercises.external_provider` / `exercises.external_id`                                                                        |
| `name`                            | `exercises.name`                                                                                                               |
| `type`                            | `exercises.type` (`exercise_type`)                                                                                             |
| `equipment`                       | `exercises.equipment` (`equipment`)                                                                                            |
| `muscleGroups[].muscle` / `.role` | `exercise_muscle_groups.muscle` / `.role`, one row each, linked by `exercise_id`                                               |
| order of `muscleGroups[]`         | `exercise_muscle_groups.position`, from 1                                                                                      |
| `instructions.setup`              | `exercises.setup_steps` (`text[]`)                                                                                             |
| `instructions.execution`          | `exercises.execution_steps` (`text[]`)                                                                                         |
| `instructions.tips`               | `exercises.tips` (`text[]`)                                                                                                    |
| `media.image.uri`                 | `exercises.image_uri`                                                                                                          |
| `media.video.uri`                 | `exercises.video_uri`                                                                                                          |
| `relatedLinks` (1.2)              | `exercises.related_links` (`jsonb`, the list as in the format; checked by `related_links_are_valid`; never written by the app) |

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

`routines.is_favorite` marks the routines the user is following now (default `false`). The app lists them first and proposes the next session among them. It is a user preference, not part of the training data format.

`exercise_settings` holds a user's settings for one exercise, catalogue or their own. It is a user setting, not part of the training data format, so it is never exported or imported.

| Column         | Meaning                                                                      |
| -------------- | ---------------------------------------------------------------------------- |
| `user_id`      | Owner; defaults to the caller                                                |
| `exercise_id`  | The exercise; deleting it deletes its settings                               |
| `rest_enabled` | Rest timer between sets of this exercise is on (default `true`)              |
| `rest_seconds` | Rest between sets, 0–3600 seconds (default 90); kept when rest is turned off |

The key is `(user_id, exercise_id)`, which is also the upsert key: saving a setting again updates it. The setting applies in every session that uses the exercise. The running timer lives on the device; the database stores no timer.

## Tombstones

`tombstones` records the rows the server deleted, so the app can delete them too: a pull never returns a deleted row. It is not part of the training data format.

| Column       | Meaning                                                                     |
| ------------ | --------------------------------------------------------------------------- |
| `id`         | The tombstone's own id; breaks ties in the pull cursor                      |
| `user_id`    | Owner of the deleted row                                                    |
| `table_name` | The table of the deleted row (see below)                                    |
| `row_id`     | Id of the deleted row; the exercise id for an exercise setting              |
| `updated_at` | When the row was deleted; the pull reads tombstones by (`updated_at`, `id`) |

Triggers write them, never a client: every delete of a user's exercise, routine, session, entry or set records one, whoever deleted it (the app, another device, an importer with the service role) and through any cascade (a session's entries and sets). So does a muscle group, routine item or exercise setting deleted on its own (a device dropped a muscle, shortened a routine); one deleted with its exercise or routine leaves none, as its parent's tombstone already removes it. A muscle group's owner is its exercise's, so catalogue exercises and their muscle groups leave none. Inserting a row again under a deleted id (a setting: under its exercise) clears its owner's tombstone, so no tombstone names a row that exists. Deleting an account deletes its tombstones. The owner reads their own tombstones; the service role may also delete old ones.

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

## Sync

The app talks to these tables through PostgREST, as the signed-in user (`SupabaseTrainingRemoteStore`).

- **When the app syncs.** `SyncScheduler` runs `TrainingSyncEngine.sync()` when the user signs in (or the app restores the session at launch), when a workout finishes, when the app comes to the foreground and when the network comes back (offline to online). Finishing a workout only asks for a sync and carries on: it never waits for the sync nor fails because of it. Never two syncs at once: a request made during a sync makes exactly one more run after it, which sends what changed meanwhile. Signed out, nothing syncs: a sync already running stops at its next request or before it applies anything, and the sign-out waits until it has. A failed sync leaves every change pending and the next trigger tries again. Signing in again (also the debug reset, which claims the store again) first stops a sync that is running: it sends and writes nothing more, and the new one starts once it has ended.
- **One store per account.** Each account has its own local store on the device (`AccountStores`): whoever signs in sees only their own data, and the sync brings it to any device they sign in on. The store is `Application Support/Accounts/<user id>/training.store`, in the app's own container (not Documents, not the app group the widget shares), named by the user id only. Its files are protected until the device is first unlocked after a restart, as the app writes to it while locked during a workout and may sync then; they stay in the device backup like the rest of the app's data. Signing in opens the account's store (a new one fills from the server on the first sync; one opened before is as it was left) and stamps it with the user before the training screens show. Signing out, or another account signing in, first closes the account: its screens go, a workout in progress stays unfinished in its own store (starting a workout there again resumes it), its sync stops and the next account opens only once it has. Signed out, no account's store is open, and what an account leaves outside its store (the widget's routine, pending lock-screen intents, Live Activities, the URL cache) is cleared, also when the app starts with a session that ended while it was closed. The store every account shared before this is moved to the account it is stamped with when that user signs in; one stamped with nobody stays where it is and is no one's store. Nothing is deleted.
- **Account guards.** The stamp is a second check: a store stamped with another user is never stamped again and never syncs (it is only logged). The remote store of an account sends a request only while the app's Supabase client is signed in as that account, and uses its answer only if the client still is when it arrives (`RemoteSessionError`); every delete and pull also names the user (`user_id`; the exercises pull, the user or the catalogue), so a request sent with another account's token reaches none of its rows. A pull that answers any row of another user applies nothing (`TrainingSyncError.pulledRowsOfAnotherUser`), and no response goes through a URL cache. The widget shows the next routine that the app publishes for the signed-in account, and nothing while signed out. The debug sample data loads only into a new store, before it is stamped, so it never syncs; the debug reset forgets the stamp and stamps the store again for the same user, and the sample data stays on the device.
- **Push.** The unit is one finished session with its entries and sets, rows keyed by the app's own ids. The app sends them in this order: delete the sets removed on the device, then the removed entries (only rows still in that session on the server; deleting an entry deletes its sets), then upsert the session, its entries and their sets. A removed entry that still holds a set the push does not list (one an importer added after the device's last pull) is not deleted, so that set is not lost: the entry and its sets are written again unchanged, which moves their `updated_at`, and the next pull brings them back to the device. A set added between that read and the delete is not seen; the window is one request long. Each step is one request, valid on its own: an entry can turn `skipped` only once the server holds none of its sets, and children need their parent for the composite foreign keys and the `completed_at` check. A push that fails part way leaves a valid but incomplete session; pushing the same session again completes it. Every request sends all the columns the app owns, `null` included, and never `created_at` or `updated_at`.
- **Push order.** `TrainingSyncEngine` pushes only when the store's owner is the signed-in user. It sends the user's own exercises (with `exercise_muscle_groups`) first, then routines (with `routine_items`), then exercise settings, then the sessions deleted on the device, then finished sessions, then the routines and exercises deleted on the device. Every row a session, routine or setting names is then already on the server (catalogue exercises already are), a re-import can reuse the external refs of a session it removed, and an exercise is deleted only after the sessions that stopped using it. Muscle groups and routine items have no id on the device: their row ids are derived from their natural keys (exercise, muscle and role; routine and position), so pushing them again updates the same rows; one the pull brought keeps the id the server holds it under. An exercise or routine push sends its muscle groups or items only when that list changed on the device since the server last held it; otherwise it sends only its own row, so marking a routine favourite or renaming an exercise keeps the items or muscles another device added meanwhile. A push that sends the list first deletes the muscle groups or items of it the device no longer lists (one request, by parent, every id the push sends kept), so the server holds exactly the device's list in its order, and a row another client wrote under its own id for the same muscle or position cannot collide with the device's. A setting is keyed by its exercise (`exercise_settings` has no `id`: upsert on `user_id, exercise_id`). A session, routine or setting that names data that never leaves the device, or a routine or exercise the server does not hold yet, is skipped and stays pending. Each pending aggregate is tried once per push.
- **Deletions from the device.** A session, routine or exercise deleted on the device that may be on the server leaves a local tombstone; each kind goes in one delete request, once per push. The tombstone is forgotten only once the server acknowledged the delete, at the revision it was read at. A refusal (an exercise still in use) is reported and keeps it; any other error stops the push and keeps it. Deleting a row the server no longer holds is acknowledged. No command deletes a routine or an exercise yet.
- **Push failures.** A refusal of the data is recorded on that aggregate on the device, with a count and the reason; it stays pending and the push carries on with the next one. A refusal is a Postgres error of class 22 or 23 (such as a unique or check violation), or a row-level security check a written row failed (`42501`, "new row violates row-level security policy"): a row that names an exercise the user cannot see, such as one deleted on the server meanwhile. That check runs only for a signed-in user, so it says nothing about the session: a request without a valid token runs as `anon`, which has no privileges, and fails "permission denied" (also `42501`) first. Any other error stops the push: nothing that was not acknowledged is marked synced, and nothing is deleted on the device. A server fault (any other PostgREST error, such as a statement timeout) still lets the pull of the same sync run, then fails the sync, as what the pull brings may be what the push needs. No network, an expired or refused session (`42501` permission denied, `PGRST3xx`) and a client signed in as another account stop the whole sync.
- **Pull.** Per table, the rows whose (`updated_at`, `id`) is after a cursor, in that order, a page at a time; `exercise_settings` uses `exercise_id` in place of `id` (row level security limits it to one user, for whom it is unique). Rows written in one statement share `updated_at`, so the `id` breaks the tie. The cursor keeps `updated_at` as the text the server returned, never a device clock or a rounded date. `sync()` pushes first, then pulls, so the device's own changes come back as echoes, not conflicts; a push and a pull never run at the same time. A user exercise deleted on the server while a session not sent yet uses it shows how the two meet: the push of the session is refused (its entries name the exercise, `42501`), the pull brings the exercise's tombstone, which keeps the exercise and marks it changed (**Deletions from the server**), and the next push sends the exercise again, then the session.
- **Pull cursors.** One per user and table, stored in the account's store (a store reset starts again from the beginning). Each table is read from its cursor less a few seconds (5 by default), whole seconds rounded down, so rows a transaction that committed late wrote just behind the cursor are read too; applying a row twice changes nothing. The tombstones are read first, then children before their parents (sets, entries, sessions, routine items, routines, muscle groups, exercise settings, exercises), so every child read has its parent read too or already on the device, and a row read after its tombstone was written again since.
- **Applying a pull.** Nothing is applied until every table is read; then every row, parents first, and every cursor are written in one save. A failure anywhere (no network, a timeout) leaves the store and the cursors as they were. Rows the device does not hold are created with the server's ids, already synced. A row whose parent the device does not hold is skipped and its table's cursor stays before it, so the next pull reads it again; so is a done entry of an exercise the session already holds a done entry of, when the pull also brings that entry's own row (the server changed it, so the next pull may place the other). A row that breaks a format rule is passed over, and so is a muscle group under an exercise that is neither the catalogue's nor one of the user's on the server (a muscle-group row names no owner). A row the device deleted, whose deletion has not reached the server yet, is not brought back, and neither are the entries and sets of a session it deleted: they are passed over, not held, so their cursors move on. Rows missing from a pull are never deleted on the device; server deletions arrive as tombstones.
- **Deletions from the server.** Tombstones are applied before the rows, children first (sets, entries, sessions, routine items, routines, muscle groups, exercise settings, exercises). A muscle group or routine item is found by the id the server holds it under; an exercise used only by routine items this pull deleted goes too. A deleted row goes from the device, unless its aggregate has a change waiting to be pushed: then it is kept and the next push writes it back, so a delete elsewhere never silently drops an edit made here (the conflict rule below). For a muscle group or routine item the change that counts is one of its list, not of its parent. Applying a deletion leaves no local tombstone and marks nothing changed, so it is never echoed back. A deleted routine leaves its sessions without it, as on the server. A user exercise the device still uses (a workout in progress, a session not sent yet) is kept and marked changed, so the next push writes it back. Each decision is reported (`SyncPullReport.deletions`).
- **Imported data and the device's choices.** Imported sets merge through the same rules as the in-app import (one entry per exercise, re-imports update values, regrouped sets move). The device's annotations are the app's: a pull never takes `warmup` of an imported set from the server for a set the device holds, nor a reconciliation choice, except one the user made (`decided_by = 'user'`, so on another device) when the session has no local change; a missing or `default` decision, all an importer writes, never replaces the device's. `superseded` is always derived from the entry's choice. A new entry ref becomes one of the entry's refs, so a later in-app import finds the entry. The server holds one done entry per exercise per session: a done entry the device does not hold, of an exercise the session already has a done entry of on the device, is that entry (an importer on the server and the in-app importer both brought the exercise). The device's entry takes the server's id, the server's sets merge into it through the import rules, and the next push sends the device's sets under that id; an entry the device had already sent under its old id leaves a tombstone for it. Its external ref on the server stays the importer's, so the importer finds it again; the device's own stays one of the entry's refs on the device. An entry ref or imported set the device holds on another entry than the server (an importer regrouped it) moves to the server's entry, as the in-app import moves it, and the entry it left is tidied the same way; so the device never pushes an empty ref over the server's, nor collides with it. The server keeps one ref per entry (its `externalRef`); the other refs merged into an entry stay on the device, as the in-app import finds an entry through its session and exercise anyway.
- **Templates.** A pulled exercise, routine or setting takes every field the push sends: muscle groups take the server's order (rows at the same position, as the seed writes them, in id order), a routine item the row at its position. A muscle group or item another client wrote under its own id keeps that id on the device, and goes up under it, until the aggregate is edited there. A routine with an item that lost its exercise is not pushed.
- **Conflicts (confirmed by the owner).** Per aggregate (a session with its entries and sets, a routine with its items, an exercise with its muscle groups, an exercise setting): when the device has a change of it waiting to be pushed, its user-edited fields keep the device's values, which the next push sends; otherwise the server's values are applied. A deletion follows the same rule (`SyncConflictRule`). An exercise's muscle groups and a routine's items are one list, decided apart from their parent: the device's list wins only when it changed on the device since the server last held it; otherwise the server's list (its rows and deletions) is applied, even while the parent waits with a change of its own, such as a favourite. Imported sets merge either way. Catalogue exercises are always the server's.
- **Echo.** A pull never marks an aggregate changed for what the server already holds, nor for a value the device only kept as it was (so two devices never push the same annotation back and forth). A session the pull changed into something the server does not hold (a reconciliation the merge decided, new server values next to a value the device keeps) is marked changed, so the next push sends the device's version.
- **External refs held under another id.** A push refused with 23505 because the server holds the same external ref under another id (an importer on the server and the in-app importer brought the same data) is resolved by the pull: the local exercise, routine, session, entry or set takes the server's id, and the next push updates that row. A local entry or set that was already sent under its old id leaves a tombstone for it.
- **Local state.** The app keeps what it needs to push on the device, never in these tables. Each account's store is stamped with its user (see **One store per account**). Every change raises a revision of its aggregate (session with entries and sets, routine, exercise, exercise setting) in the same save, and the aggregate is marked synced only at the revision the server acknowledged, so an edit during the upload is pushed again. An exercise and a routine also keep a fingerprint of their muscle groups or items as the server last held them (written when a push that sent the list is acknowledged and when a pull applies the server's list); it is built from the list's content (order and every field pushed), so saving the same list again is no change. Sessions in progress, catalogue exercises and data written before any sign-in (the debug sample data) are never pushed. Deleting a row that may be on the server keeps a local tombstone: removed sets and entries travel with their session's next push, removed sessions on their own.
