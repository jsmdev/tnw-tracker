# Deploy Runbook — tnw-tracker

This document explains how to manage deployments for tnw-tracker.

---

## Environments

| Environment | Branch    | Supabase project   |
| ----------- | --------- | ------------------ |
| Development | `develop` | `tnw-tracker-dev`  |
| Production  | `main`    | `tnw-tracker-prod` |

---

## How to approve a production deploy

Production deploys run on every push to `main` but the `production` environment in GitHub requires a manual approval gate.

1. Push to `main` (or merge a PR).
2. Go to **Actions** → **Deploy Prod** workflow run.
3. You will see a "Waiting for review" step on the `migrate` job.
4. Click **Review deployments** → check `production` → click **Approve and deploy**.
5. The `supabase db push` step will run against the production database.

> **Note**: Only users with the "Required reviewer" role on the `production` environment can approve. Add reviewers at **Settings → Environments → production → Required reviewers**.

---

## How to rollback a Supabase migration

Supabase migrations are forward-only by design. To roll back:

### Option A — Write a new down migration (recommended)

```bash
# Locally
supabase migration new rollback_<migration_name>
# Edit the generated file in supabase/migrations/
# Apply it to dev first, then merge to develop → main
```

### Option B — Manual SQL rollback (emergency only)

```bash
# Connect to the remote DB
supabase db connect --project-ref <project-ref>

# Run your rollback SQL manually
ALTER TABLE ...;
DROP TABLE ...;
```

Then create a new migration file that reflects the rolled-back state so the local and remote schemas stay in sync.

---

## How to add a new secret

### GitHub Actions secret (per environment)

1. Go to **Settings → Secrets and variables → Actions**.
2. Select the environment (`development` or `production`).
3. Click **New environment secret**.
4. Add the name and value.
5. Reference it in workflows as `${{ secrets.SECRET_NAME }}`.

---

## How to link a new dev environment locally

```bash
# 1. Install Supabase CLI
brew install supabase/tap/supabase

# 2. Login
supabase login

# 3. Link to the dev project
supabase link --project-ref <dev-project-ref>

# 4. Pull the latest schema
supabase db pull

# 5. Start local Supabase stack
supabase start
```

---

## Secrets reference

| Secret name             | Environment | Description                                   |
| ----------------------- | ----------- | --------------------------------------------- |
| `SUPABASE_ACCESS_TOKEN` | dev + prod  | Supabase personal access token                |
| `SUPABASE_PROJECT_REF`  | dev + prod  | Project reference ID (e.g. `abcdefghijklmno`) |
| `SUPABASE_DB_PASSWORD`  | dev + prod  | Database password                             |

---

## Monitoring

- **Supabase logs**: Dashboard → Logs → API/DB/Auth
- **GitHub Actions**: Actions tab → filter by workflow name
- **CodeQL alerts**: Security → Code scanning alerts

# CI Test
