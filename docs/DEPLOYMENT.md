# Deployment, Updates, and Rollback

The app runs on Vercel as a container. Both environments deploy the **full Rails
app** (PostgreSQL, Clerk, officer/member flows) from the same `Dockerfile.vercel`
— not the database-free browser demo.

| Stage | Vercel project | URL |
| --- | --- | --- |
| Production | `pt500` | https://pt500.vercel.app |
| Dev / staging | `pt500-dev` | https://pt500-dev.vercel.app |

Both live in the `tiernan-lindauers-projects` Vercel team.

## How it works

Vercel detects `Dockerfile.vercel` at the repository root, builds the image,
pushes it to the Vercel Container Registry, and runs it as a container function
on Fluid compute.

- Puma serves HTTP directly on **`PORT`**, default **80** (no Thruster). It loads
  Rails before opening the listening socket, so Vercel cannot send traffic
  through a proxy that is already listening while Rails is still starting (which
  caused 502s on the request that triggered a cold start).
- Rails serves the precompiled static assets (`public_file_server` enabled).
- Container instances are **stateless** and scale to zero after 5 minutes idle.
  All persistent state lives in the attached PostgreSQL database
  (`DATABASE_URL`).
- Migrations apply when an instance boots: `bin/vercel-entrypoint` runs
  `bin/rails db:migrate` before the server starts. Because several instances can
  cold start at once, it retries while another instance holds the migration
  advisory lock (`db:prepare` schema-loads an empty database and can corrupt it,
  so it is not used).
- `config/environments/production.rb` allows the `.vercel.app` hosts and enables
  `public_file_server` so Puma serves the precompiled assets.

## Continuous deployment

`.github/workflows/deploy.yml` deploys on every push:

| Branch | Deploys to |
| --- | --- |
| `dev` | `pt500-dev` |
| `main` | `pt500` (production) |

Promote changes `test -> dev -> main` through pull requests. Pull requests and
pushes to `test` run `.github/workflows/ci.yml` (Brakeman, bundler-audit,
RuboCop, RSpec, JS tests); pushes to `dev` and `main` additionally deploy.

Required repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
| --- | --- |
| `VERCEL_TOKEN` | Vercel access token (Account Settings → Tokens) |
| `VERCEL_ORG_ID` | `team_FwG5MDE3sw2Y9mAfZG9bkUDG` |
| `VERCEL_PROJECT_ID_DEV` | Project id of `pt500-dev` (`.vercel/project.json` after `vercel link`) |
| `VERCEL_PROJECT_ID_PROD` | Project id of `pt500` |

## Environment variables

Set per project (Vercel → Project → Settings → Environment Variables) or with
`vercel env add`. Never commit real values.

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection string (Heroku Postgres, Neon, or another provider) |
| `RAILS_MASTER_KEY` | Decrypts Rails credentials (matches `config/master.key` locally) |
| `CLERK_SECRET_KEY` | Clerk server key |
| `CLERK_PUBLISHABLE_KEY` | Clerk browser key |
| `CLERK_SIGN_IN_URL` | Clerk Account Portal sign-in URL |
| `CLERK_SIGN_UP_URL` | Clerk Account Portal sign-up URL |
| `OFFICER_EMAILS` | Comma-separated emails that get the officer role on sign-in |
| `RAILS_SERVE_STATIC_FILES` | `true` (also baked into the Vercel image) |

`RAILS_ENV=production` is baked into the image.

## Clerk return URLs

For the shared development Clerk instance, Account Portal → Paths → Fallback
development host is `https://pt500.vercel.app`. Under Redirects, the after-sign-in,
after-sign-up, and logo-click paths are `/`. These settings keep direct portal
visits from returning to the legacy Heroku app.

The Rails sign-in link explicitly supplies the current request origin as the
return URL, so staging and preview sign-ins return to their own deployment.
When JavaScript is available, it waits for Clerk and uses its redirect method
to carry development-session context into the portal. If the browser already
has a session, it refreshes Rails to read the newly synchronized cookie.
The Clerk browser script must receive `data-clerk-publishable-key` before it
executes; passing the key to `Clerk.load()` is too late to initialize the SDK.

After changing these settings, reload the app and verify sign-in, the account
portal logo, and sign-out on both Vercel environments. An already-open portal
can retain the previous development host until its client refreshes.

## First-time project setup

The Vercel projects are already created. To recreate or link from scratch:

```bash
vercel project add pt500-dev --scope tiernan-lindauers-projects
vercel project add pt500     --scope tiernan-lindauers-projects

vercel link --project pt500-dev --scope tiernan-lindauers-projects
vercel env add DATABASE_URL production        # repeat for each variable above
vercel deploy --prod                           # manual deploy
```

## Manual deploy

CI handles deploys, but a one-off deploy from a linked checkout works too:

```bash
vercel deploy --prod --yes --scope tiernan-lindauers-projects
```

## Rollback

Vercel keeps every deployment. Promote a previous one back to production from
the dashboard (Project → Deployments → … → Promote to Production), or redeploy
the older commit:

```bash
git checkout <good-commit>
vercel deploy --prod --yes --scope tiernan-lindauers-projects
```

> Rollback restores the **code** only. It does **not** reverse database
> migrations. If a deploy ran a destructive migration, restore the database
> (below) or write a compensating migration.

## Database recovery

`DATABASE_URL` points at a managed PostgreSQL instance. Back it up with
`pg_dump` and restore with `pg_restore`/`psql`:

```bash
pg_dump "$DATABASE_URL" --format=custom --file=backup.dump
pg_restore --clean --no-owner --dbname="$DATABASE_URL" backup.dump
```

Restores are destructive: capture a fresh backup first.

## Cost

Vercel Hobby and the PostgreSQL provider's free tier keep this at $0 for a small
class project. Watch the Vercel function **Active CPU** usage and the database
connection limit; both environments share the same Clerk application unless a
separate one is configured.

## Heroku (legacy)

Earlier deployments ran on Heroku (`tlind-pts` production, `tlind-pts-dev`
staging) via the `heroku`/`heroku-dev` git remotes and the `pts` pipeline. The
`Procfile`, `app.json`, and Heroku Postgres addons are still in the repo. Push
with `git push heroku-dev main:main` / `git push heroku main:main` if a Heroku
fallback is ever needed.

## Local development

See the "Setup" and "Database" sections of the [README](../README.md).
