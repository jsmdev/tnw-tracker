# Training data format

This document defines the provider-neutral format the app uses for exercises, routines and performed sessions. It is the contract between the app and any importer, and the basis for the database schema and the app's data model.

- **Schema:** [`training-data/schema.json`](training-data/schema.json) (JSON Schema 2020-12)
- **Examples:** [`training-data/examples/`](training-data/examples), all with invented data
- **Validator:** [`training-data/validate.py`](training-data/validate.py)
- **Format version:** 1.1 (1.1 adds `relatedVideos` to the exercise; a 1.0 bundle is still valid)

## Why it exists

The app keeps one training history made of two kinds of data:

- sets the user logs by hand in the app, and
- sets recorded by connected gym machines, which arrive later through an import that lives outside this repository.

The app does not know who makes those machines. An importer translates whatever its source provides into this format; the app only reads this format. Nothing in the format, the schema or the examples names a provider's fields, categories or codes.

## Principles

1. **Neutral vocabulary.** Enumerations are small and defined here. An importer maps its source to them; values that do not map are left out, never passed through. The schema rejects unknown properties.
2. **Identity by origin.** Every item has an `id` that links the parts of a bundle together. Imported items also carry an `externalRef`, which is their identity outside the bundle and what makes a re-import safe.
3. **Unambiguous time.** Timestamps are RFC 3339 with an explicit offset, normally UTC. A session also stores its IANA time zone so local dates can be shown.
4. **Explicit units.** Durations are whole seconds, distances are metres, and a weight always states its unit.
5. **Nothing is lost.** When manual and imported sets overlap, the ones that do not count are marked, not deleted.
6. **Optional means unknown.** A missing field means the source did not provide it. Importers never invent values to fill a gap.

## Structure

A bundle is one JSON document:

| Field           | Required | Meaning                                                                                |
| --------------- | -------- | -------------------------------------------------------------------------------------- |
| `formatVersion` | yes      | `1.x`. Readers reject a major version they do not know.                                |
| `generatedAt`   | yes      | When the bundle was produced.                                                          |
| `source`        | yes      | `provider`: slug of the system that produced the bundle, for example `app`.            |
| `locale`        | no       | Language tag of every text in the bundle, for example `en` or `es-ES`.                 |
| `exercises`     | yes      | Catalogue entries. Every exercise referenced elsewhere in the bundle must be included. |
| `routines`      | no       | Session templates.                                                                     |
| `sessions`      | yes      | Performed sessions.                                                                    |

Bundles are self-contained: a reference to an exercise or routine always resolves inside the same bundle.

```
bundle
├── exercises[]
├── routines[]
│   └── items[]      → exercise
└── sessions[]       → routine (optional)
    └── entries[]    → exercise
        └── sets[]   strength, bodyweight and cardio
```

There are two kinds of bundle, and they differ only in what they contain:

- **An importer's bundle** holds what one provider recorded: every set is `imported`, and there is no `reconciliation`.
- **The app's bundle** (`source.provider` is `app`) is an export of the app's history. It can hold manual and imported sets side by side, with the result of reconciling them.

## Entities

### Exercise

| Field           | Required | Meaning                                                                                   |
| --------------- | -------- | ----------------------------------------------------------------------------------------- |
| `id`            | yes      | UUID.                                                                                     |
| `externalRef`   | no       | Identity in the provider's catalogue.                                                     |
| `name`          | yes      | Display name.                                                                             |
| `type`          | yes      | `strength`, `bodyweight` or `cardio`. Decides how the exercise is logged.                 |
| `equipment`     | no       | `none`, `free_weights`, `machine`, `connected_machine`, `cardio_machine` or `other`.      |
| `muscleGroups`  | no       | List of `{ muscle, role }`, with `role` being `primary` or `secondary`.                   |
| `instructions`  | no       | `setup`, `execution` and `tips`, each a list of steps.                                    |
| `media`         | no       | `image` and `video`, each with a `uri`: absolute, or relative to an agreed media root.    |
| `relatedVideos` | no       | Since 1.1. External videos that explain the exercise: a list of `{ title, url, source }`. |

`relatedVideos` are curated with the catalogue, not written by the user: `title` is our own title, shown instead of the address; `url` is an `https` address; `source` is the name of the site shown to the user (for example YouTube). The list is never empty and lists no video twice, and an exercise without the field keeps the videos the receiver already holds for it (principle: optional means unknown).

`connected_machine` marks the exercises whose sets can arrive by import, so the app knows where reconciliation may apply.

When a provider has no catalogue record for something the user did, the importer still emits an exercise with the three required fields: `name` is the label the provider shows for that activity, and `type` follows from the data, `cardio` when its sets only have a duration. See [`exercise-without-catalogue-data.json`](training-data/examples/valid/exercise-without-catalogue-data.json).

### Routine

A routine is a session template: an ordered list of exercises with targets.

| Field         | Required | Meaning                        |
| ------------- | -------- | ------------------------------ |
| `id`          | yes      | UUID.                          |
| `externalRef` | no       | Only for imported routines.    |
| `name`        | yes      | Display name.                  |
| `description` | no       | Free text.                     |
| `items`       | yes      | At least one, described below. |

| Field (item)            | Required | Meaning                    |
| ----------------------- | -------- | -------------------------- |
| `order`                 | yes      | Position, starting at 1.   |
| `exerciseId`            | yes      | The planned exercise.      |
| `targetSets`            | no       | Number of sets.            |
| `targetReps`            | no       | `{ min, max }` range.      |
| `targetWeight`          | no       | `{ value, unit }`.         |
| `targetDurationSeconds` | no       | For timed sets and cardio. |
| `restSeconds`           | no       | Rest between sets.         |
| `notes`                 | no       | Free text.                 |

Targets are ranges and optional on purpose. Together with the history of an exercise they are what a later version needs to propose the next session: which routine comes next, and what load to try.

### Session

| Field             | Required | Meaning                                                          |
| ----------------- | -------- | ---------------------------------------------------------------- |
| `id`              | yes      | UUID.                                                            |
| `externalRef`     | no       | Only for imported sessions.                                      |
| `completedAt`     | yes      | When the session ended. No entry is completed later.             |
| `timeZone`        | yes      | IANA zone, for example `Europe/Madrid`.                          |
| `startedAt`       | no       | Unknown for imported sessions.                                   |
| `durationSeconds` | no       | Training time. Never longer than the time between start and end. |
| `routineId`       | no       | The routine the session was started from, if any.                |
| `name`, `notes`   | no       | Free text.                                                       |
| `entries`         | yes      | At least one.                                                    |

A session without `routineId` is a free session: the user added exercises as they went.

### Entry

One exercise inside a session.

| Field                | Required  | Meaning                                                          |
| -------------------- | --------- | ---------------------------------------------------------------- |
| `id`                 | yes       | UUID.                                                            |
| `externalRef`        | no        | Identity of the entry in the provider's history.                 |
| `exerciseId`         | yes       | The exercise performed.                                          |
| `order`              | yes       | Position in the session, starting at 1.                          |
| `status`             | yes       | `done`, `skipped` or `removed`.                                  |
| `replacedExerciseId` | no        | The exercise the routine planned here, when the user swapped it. |
| `completedAt`        | no        | When the exercise was finished, if known.                        |
| `sets`               | if `done` | At least one.                                                    |
| `reconciliation`     | see below | See [Reconciliation](#reconciliation).                           |
| `notes`              | no        | Free text.                                                       |

- `done`: performed. It has at least one set.
- `skipped`: it was in the session and the user did not perform it. It has no sets.
- `removed`: the user took it out of the session. It is kept so the session can be compared with its routine. Any sets it had stay stored and do not count.

**One entry per exercise.** A session has at most one `done` entry for a given exercise. Coming back to an exercise later in the session adds sets to the same entry. This is what makes "the same exercise in the same session" a single place, which reconciliation relies on.

### Set

A set is the unit of work for every type of exercise. Which fields it carries depends on the exercise's `type`:

| Exercise type | Fields                                                                |
| ------------- | --------------------------------------------------------------------- |
| `strength`    | `reps` and `weight`; `durationSeconds` if the source reports it.      |
| `bodyweight`  | `reps`, or `durationSeconds` for a timed hold. Normally no weight.    |
| `cardio`      | `durationSeconds`, and `distanceMeters` if known. No reps, no weight. |

| Field             | Required           | Meaning                                                                                 |
| ----------------- | ------------------ | --------------------------------------------------------------------------------------- |
| `id`              | yes                | UUID.                                                                                   |
| `order`           | yes                | Position among the sets of the same `source` in the entry, starting at 1.               |
| `source`          | yes                | `manual` (logged by hand in the app) or `imported`.                                     |
| `externalRef`     | if `imported`      | The key that prevents duplicates.                                                       |
| `reps`            | `reps` or duration | Repetitions.                                                                            |
| `durationSeconds` | `reps` or duration | Length of a timed set or cardio segment, or time under load when the source reports it. |
| `distanceMeters`  | no                 | Cardio only. Requires `durationSeconds`.                                                |
| `weight`          | no                 | `{ value, unit }` with `kg` or `lb`. Omitted when there is no added weight.             |
| `rir`             | no                 | Reps in reserve, 0 to 10.                                                               |
| `restSeconds`     | no                 | Rest taken after the set.                                                               |
| `completedAt`     | no                 | Imported sets usually have no timestamp of their own.                                   |
| `superseded`      | no                 | `true` when reconciliation kept the other source. Defaults to `false`.                  |
| `warmup`          | no                 | `true` for a warm-up set, manual or imported. Defaults to `false`.                      |

A weight of zero is a real load of zero. "No weight" is expressed by leaving `weight` out.

### Cardio

Cardio has no structure of its own: a cardio entry is an entry whose sets have a duration and, when known, a distance.

- A continuous effort is one set.
- A source that records an effort in segments gives one set per segment, in order.
- The totals of the entry are the sums over its sets that are neither superseded nor warm-up sets.

See [`cardio.json`](training-data/examples/valid/cardio.json).

## Identity and re-imports

An import can run many times over the same period. It must never create duplicates.

- **`externalRef`** is `{ provider, id }`. It is unique per provider and kind of item, and it is the key the receiver upserts on.
- **`id`** is a UUID in canonical lower-case form, unique among items of the same kind within the bundle. It links the parts of the bundle together (which sets belong to which entry, which exercise an entry refers to). For an item without an `externalRef`, the `id` is also its identity: items created in the app keep the app's own id.
- **Receivers own their keys.** A receiver never uses the `id` of an imported item as its own key. It looks the item up by `externalRef`; if it is new, the receiver gives it a fresh identifier of its own (for example a UUID version 7). This keeps users apart: two users importing the same source item never share or collide on a key, and nobody can guess another user's keys from public source ids. It follows RFC 9562, section 6.13, which advises against name-based UUIDs as primary keys.
- **Deterministic bundle ids (recommended).** An importer may still derive its ids, so every run produces the same bundle for the same data and two exports can be compared: the UUID version 5 of the name `{provider}:{kind}:{externalId}` in the namespace `6f1d2c3a-0b4e-4c5d-8e6f-7a8b9c0d1e2f`, where `kind` is `exercise`, `routine`, `session`, `entry` or `set`. These ids stay inside the bundle.
- **Catalogue exercises.** A receiver may hold a curated catalogue of its own. Its exercises never carry an `externalRef`. An imported exercise is always the importing user's own item, looked up by its `externalRef` like any other imported item. An exercise without an `externalRef` is matched by `name` and `type`.
- **Sources without ids.** Some sources identify an entry but not its sets, and have no session at all. The importer then derives the missing references from what is stable:
  - a set: the entry's external id plus the set's position, as in `5001#2`;
  - a session: the provider's own grouping of entries, as in `2030-03-04`. Its `completedAt` is the latest `completedAt` of its entries.
- **Updates.** When an item with a known `externalRef` arrives again, its values replace the stored ones. An import only ever writes imported data: it never changes or removes manual sets, and it never changes `superseded`, `warmup` or `reconciliation`, which belong to the app. On an imported set, `warmup` is the user's annotation.
- **Regrouped entries.** When an imported entry or set arrives inside a different session than the one that holds it, the receiver moves it to the new session and keeps the app's annotations on it. A session that only held imported data and is left with no counted set is removed. A session with manual sets is never removed by an import.
- **Deleting sessions.** An import over the same period recreates any imported data it does not find, so a deleted session that held imported data comes back. The app therefore lets the user delete a completed session only when it holds none (no `externalRef` on the session or its entries, and no imported set).
- **Partial imports.** A receiver validates and writes each session on its own. An invalid session is skipped and reported, and nothing of it is written; the other sessions of the bundle are imported. Errors in the bundle itself (its version, or an exercise or routine it references) reject the whole bundle.

## Reconciliation

The user may log sets by hand on a connected machine, and the machine's own sets may arrive hours later. Reconciliation decides which ones count. It applies to every type of exercise, cardio included.

1. **Unit.** Reconciliation works per entry: one exercise in one session.
2. **Merging.** When imported sets arrive for an exercise the user already has a `done` entry for in that session, the app adds them to that entry. The entry keeps its `id` and gains the imported entry's `externalRef`. No second entry is created.
3. **Trigger.** An entry needs reconciliation when it holds sets from both sources. It then has a `reconciliation` object; an entry with a single source never has one.
4. **Default.** The imported sets are kept: `reconciliation` is `{ keep: "imported", decidedBy: "default" }` and every manual set of that entry gets `superseded: true`.
5. **User choice.** The user can keep their own sets instead: `{ keep: "manual", decidedBy: "user" }`. Now the imported sets are the superseded ones. The user can go back to the imported sets, which is recorded as `{ keep: "imported", decidedBy: "user" }`. A default decision always keeps the imported sets.
6. **Nothing is deleted.** Superseded sets stay stored. History, personal records and estimated one-rep max only read sets that are not superseded. Volume, personal records and estimated one-rep max also leave out warm-up sets. Warm-up sets do not change the trigger: it looks at the sources of all the sets of the entry.
7. **Re-imports respect the choice.** A later import updates the imported sets' values and leaves the manual sets, `reconciliation`, `superseded` and `warmup` as they are.

`reconciliation` may also carry `decidedAt`, the moment the default was applied or the user chose.

See [`reconciliation.json`](training-data/examples/valid/reconciliation.json) for both outcomes.

## Validation

```sh
pip install -r docs/training-data/requirements.txt
python docs/training-data/validate.py               # the examples
python docs/training-data/validate.py bundle.json   # your own bundle
```

The validator runs in CI on pull requests to `develop` and `main` (`training-data-format` job). It checks two things:

| Step       | What it checks                                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Schema     | Structure, required fields, enumerations, number ranges, timestamps with an offset, canonical UUIDs, and no unknown properties. |
| Rule check | What a JSON Schema cannot express. Each rule has a name, listed below.                                                          |

| Rule                     | Meaning                                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `unique-id`              | No two items of the same kind share an `id`.                                                                 |
| `unique-external-ref`    | No two items of the same kind share an `externalRef`.                                                        |
| `exercise-reference`     | Every `exerciseId` and `replacedExerciseId` names an exercise in the bundle.                                 |
| `routine-reference`      | Every `routineId` names a routine in the bundle.                                                             |
| `order`                  | Positions are unique: entries in a session, items in a routine, and sets of one source in an entry.          |
| `one-entry-per-exercise` | A session has at most one `done` entry per exercise.                                                         |
| `reconciliation`         | `reconciliation` is present exactly when an entry mixes sources, and `superseded` marks the source not kept. |
| `exercise-type`          | Cardio sets have a duration and neither reps nor weight; only cardio sets have a distance.                   |
| `range`                  | `min ≤ max`, `startedAt ≤ completedAt`, the duration fits in the session, no entry ends after its session.   |

Every file in `examples/valid` must pass. Every file in `examples/invalid` breaks one rule, and must fail for exactly the rule and location listed in `examples/invalid/expected.json`.

The validator does not check that a `timeZone` exists in the IANA database, that a media `uri` can be fetched, or that an `id` was derived as described above.

## Examples

| File                                   | Shows                                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------------------------ |
| `connected-machine-strength.json`      | An importer's bundle: no per-set timestamp, derived ids, time under load, a related video. |
| `routine-session.json`                 | A routine and a session from it: a warm-up set, a swap, a skip, a removal.                 |
| `bodyweight-and-timed-sets.json`       | A free session with sets that have reps but no weight, and timed sets.                     |
| `cardio.json`                          | Imported cardio in three segments, and manual cardio with only a duration.                 |
| `exercise-without-catalogue-data.json` | An exercise the provider has no catalogue record for.                                      |
| `reconciliation.json`                  | Manual and imported sets in one entry, kept by default and kept by the user.               |

## Assumptions and open decisions

These are not settled. Each has the default this version assumes, so work can continue; changing one means a new format version.

| #   | Question                                                                                                           | Assumed for now                                                                                                                                                                  |
| --- | ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| O1  | Which manual session do imported entries join?                                                                     | The one completed on the same local date. If there is none, the app creates a session. The format does not encode this rule.                                                     |
| O2  | Is reconciliation per entry or per set?                                                                            | Per entry. Keeping some sets from each source in one entry is not possible.                                                                                                      |
| O3  | Can the same exercise appear twice in a session?                                                                   | No: one `done` entry per exercise. Returning to an exercise adds sets to its entry, so the order of sets across exercises is not recorded.                                       |
| O4  | What is the `source` of data the user typed into the gym's own app, or that reached the provider from another app? | `imported`: `manual` only means "logged by hand in this app". The provenance inside the provider is dropped.                                                                     |
| O5  | A source may give local times without an offset.                                                                   | The importer converts them to UTC using the source's time zone. If the source's times were already UTC, sessions near midnight would shift.                                      |
| O6  | A source may not state its weight unit.                                                                            | The importer must write a unit; it assumes the unit configured for the source.                                                                                                   |
| O7  | Where do images and videos live?                                                                                   | Private bucket `exercise-media`; `media.uri` is the immutable object path `<user_id>/<exercise_id>/<file>`. Users read only their own folder; the app caches by path.            |
| O8  | Extra cardio metrics (heart rate, speed, incline) and energy.                                                      | Not part of version 1.0. Speed can be derived from distance and duration.                                                                                                        |
| O9  | Per-set details some machines report, such as an eccentric mode or one-sided work.                                 | Not part of version 1.0.                                                                                                                                                         |
| O10 | Warm-up sets and RPE.                                                                                              | Warm-up sets are part of version 1.0 (`warmup`). RPE is not; effort is expressed with `rir` only.                                                                                |
| O11 | Texts in several languages.                                                                                        | One language per bundle, stated in `locale`.                                                                                                                                     |
| O12 | Grouping routines into a plan with an order or a calendar.                                                         | Not part of version 1.0. Routines stand alone.                                                                                                                                   |
| O13 | Sessions derived by an importer have no natural id.                                                                | The importer derives one from the provider's grouping. If the provider regroups entries, the session reference changes; receivers then move the entries (see Regrouped entries). |
| O14 | Muscle vocabulary.                                                                                                 | Thirteen groups, listed in the schema. Finer anatomy and per-muscle weights are dropped.                                                                                         |

## Out of scope

- How an importer reads its source. That lives outside this repository.
- The database tables and the app's persistence model. They follow this format, and each is defined in its own issue.
- Body measurements, health data and anything not about training sessions.
