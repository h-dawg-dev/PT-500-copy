# Ownership and Access

## Environments

| Environment | URL | Platform | Database | Owner |
| --- | --- | --- | --- | --- |
| Production | https://tlind-pts-bfd5ca266875.herokuapp.com/ | Heroku app `tlind-pts` (pipeline `pts`, production stage) | Heroku Postgres addon on `tlind-pts` | Tiernan Lindauer |
| Staging / dev app | https://tlind-pts-dev-442d7fd7a3a8.herokuapp.com/ | Heroku app `tlind-pts-dev` (pipeline `pts`, staging stage) | Heroku Postgres addon on `tlind-pts-dev` | Tiernan Lindauer |
| Local development | http://localhost:3000 | Docker Postgres or the dev Heroku Postgres | `pt_society_development` or `tlind-pts-dev` | Individual developer |

## Accounts and platforms

| Asset | Owner / holder | Notes |
| --- | --- | --- |
| GitHub repo | `FA26-CSCE431-software-engineering/PT-500` (private, org-owned) | Default branch `main`; working branches `dev` and `test` |
| GitHub board | Repo **Projects** tab | Sprint/task tracking for the course team |
| Heroku apps | Personal account `tiernanlind@tamu.edu` | Ownership transfer to **Hudson (`hudson.qml@tamu.edu`)** is in progress — see below |
| Clerk (sign-in) | Held in Heroku config vars and local `.env` | Dashboard access needed to rotate keys or manage sign-in |
| Officer emails | `OFFICER_EMAILS` config var, per environment | See [ADMIN_GUIDE.md](ADMIN_GUIDE.md) |

## In-progress: Heroku ownership transfer

Ownership of both apps is being handed to Hudson (`hudson.qml@tamu.edu`). Two app transfer requests were created and are **pending acceptance** by Hudson:

- `tlind-pts` → hudson.qml@tamu.edu (pending)
- `tlind-pts-dev` → hudson.qml@tamu.edu (pending)

Once Hudson accepts both, he owns the apps, their Postgres addons, config vars, and the `papertrail` addon. Hudson must have a Heroku account using that exact email.

The `pts` **pipeline cannot be transferred to a personal account** — Heroku only allows pipeline transfers to a team/org the current owner administers. After the apps move, either:

1. Hudson recreates a `pts` pipeline from his account and adds the two apps, or
2. both parties join a Heroku team/org, and the pipeline is transferred to that team.

## How to get access

- **GitHub**: ask an org owner to add you to `FA26-CSCE431-software-engineering` (or as a repo collaborator).
- **Heroku**: an app owner runs `heroku access:add EMAIL -a tlind-pts` (and `-a tlind-pts-dev`).
- **Officer role**: add the email to `OFFICER_EMAILS` on that environment — see [ADMIN_GUIDE.md](ADMIN_GUIDE.md).
