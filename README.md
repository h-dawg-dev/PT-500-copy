# Physical Therapy Society

Rails 8 app for the TAMU Physical Therapy Society: member intake, attendance, and points. PostgreSQL, Clerk sign-in, member/officer roles, an event board, and officer attendance.

## Documentation

Handover and operations docs live in [`docs/`](docs/README.md): [ownership](docs/OWNERSHIP.md), [deployment and rollback](docs/DEPLOYMENT.md), [user guide](docs/USER_GUIDE.md), [administrator guide](docs/ADMIN_GUIDE.md), [support](docs/SUPPORT.md), and the [deployment/support checklist](docs/DEPLOYMENT_SUPPORT_CHECKLIST.md).

## Requirements

- Ruby 3.3
- Rails 8.1
- PostgreSQL 16+ (Docker is the same pattern as the CSCE 431 book collection app)
- A [Clerk](https://clerk.com) application (secret key, publishable key, and Account Portal sign-in URL)

## Database

Default is local Docker Postgres, same as the CSCE 431 book collection app (`postgres` / `postgres` on `127.0.0.1:5432`).

If `DATABASE_URL` is set in `.env`, development uses that database normally. Leave it unset to use Docker. Tests use `TEST_DATABASE_URL` when provided, which may point to a local or hosted test database; otherwise they use `pt_society_test` with the configured host credentials. `DATABASE_URL` is not reused for tests. Do not commit `.env`.

Deployed environments run on Vercel (`pt500` for production, `pt500-dev` for dev) as containers built from [`Dockerfile.vercel`](Dockerfile.vercel). Each environment has its own `DATABASE_URL`; see [deployment](docs/DEPLOYMENT.md). Legacy Heroku apps (`tlind-pts`, `tlind-pts-dev`) still exist with their own Heroku Postgres addons.

## Setup

Copy environment variables:

```bash
cp .env.example .env
```

Fill in Clerk keys from the Clerk dashboard. Put officer emails in `OFFICER_EMAILS` (comma-separated). Those accounts become officers on first sign-in.

Start PostgreSQL. Either:

```bash
docker compose up -d db
```

or set `DATABASE_URL` in `.env` to the dev Heroku Postgres URL (`heroku config:get DATABASE_URL -a tlind-pts-dev`). With a `DATABASE_URL`, skip `db:create` — the database already exists:

```bash
bundle install
bin/rails db:migrate
bin/rails server
```

Without `DATABASE_URL`:

```bash
bundle install
bin/rails db:create db:migrate db:seed
bin/rails server
```

Open http://127.0.0.1:3000

After creating a database from its schema, run `bin/rails db:seed` to install the reference terms. Existing named terms are preserved. Administrators manage future terms as described in the [administrator guide](docs/ADMIN_GUIDE.md).

## Roles

Clerk handles identity (who signed in). This app stores authorization in Postgres:

| Role | Access |
| --- | --- |
| `member` | Own chart, event board, and whether they were marked present |
| `officer` | Same, plus posting events and marking attendance at `/officer` |

Promote someone by listing their email in `OFFICER_EMAILS` or by setting `users.role` to `officer`. Officers are not demoted on later sign-ins. Officers can also promote members from **Manage admins** in the app.

## Member intake and signup policy

New members complete the intake form after signing in. The reminder disappears
after submission, and the answers appear under **My information**, where members
can update them. Officers review responses under **Member intake forms** and on
each member record.

Officers can turn on **Require a @tamu.edu email address for new signups** in
**Society settings**. The setting is on by default and applies to new and existing
accounts on every request; officers can switch it off to test with personal
accounts. Keep the Clerk sign-up restrictions aligned when possible.

### Resetting an account for a demo

`users:reset_for_demo` puts one account back to its just-signed-up state, so the
intake form shows on the next sign-in. It deletes the person's intake responses
(including an older unlinked one under their email), RSVPs, check-ins, point
adjustments and dues records, and clears major, T-shirt size and class year. The
account and its Clerk sign-in stay. It is a dry run unless `APPLY=1`; add
`OFFICER=1` to keep or grant admin access. Run it with Heroku access to the app
(`tlind-pts` for production, `tlind-pts-dev` for staging):

```bash
heroku run -a tlind-pts "bin/rails 'users:reset_for_demo[person@tamu.edu]'"
heroku run -a tlind-pts "env APPLY=1 OFFICER=1 bin/rails 'users:reset_for_demo[person@tamu.edu]'"
```

The emails are listed under **Manage admins**.

## Events and attendance

Officers post events (title, room, time, points). Members see upcoming and past events and their own check-in status. Officers open an event roster and mark who was in the room. Points on a member chart are the sum of points from events they attended. Officers can be marked present, but their attendance earns no points and they are left off the member points report.

## Event import and CSV reports

Officers can open **Event import and CSV reports** from the dashboard to download events,
attendance and member-points reports by term or all time. Upload the GetInvolved
Excel (.xlsx) export directly to import its events; CSV UTF-8 also works. See [the CSV guide](docs/CSV_TRANSFERS.md)
for supported columns, repeat-import behavior and point defaults.

## Deployment

Pushes to `dev` deploy `pt500-dev` and pushes to `main` deploy `pt500`
(production) on Vercel through `.github/workflows/deploy.yml`. The full Rails
app runs as a container from `Dockerfile.vercel`; migrations apply on boot.
Setup, environment variables, and rollback are documented in
[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

## Tests

```bash
bundle exec rspec
node --test test/javascript/controllers.test.mjs
```

## Default database login

`config/database.yml` uses `postgres` / `postgres` on `127.0.0.1:5432` unless a URL is set for the environment. Override host credentials with `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USERNAME`, and `DATABASE_PASSWORD`. Set `TEST_DATABASE_URL` to use a dedicated test database on any host, or `TEST_DATABASE_NAME` to change the default test database name. On Windows, `gssencmode` is disabled so local libpq does not drop the connection.
