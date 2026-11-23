# 4.2 Deployment and Support Checklist

Filled for the TAMU Physical Therapy Society app (`FA26-CSCE431-software-engineering/PT-500`).

| Item | Evidence / link | Complete? |
| --- | --- | --- |
| Review / staging deployment verified | Staging app `tlind-pts-dev` — https://tlind-pts-dev-442d7fd7a3a8.herokuapp.com/ (HTTP 200) | Yes |
| Customer / production deployment verified | Production app `tlind-pts` — https://tlind-pts-bfd5ca266875.herokuapp.com/ (HTTP 200) | Yes |
| Customer access, authentication, and roles verified | Clerk sign-in; `member`/`officer` roles (`app/models/user.rb`, `app/controllers/concerns/authentication.rb`); [USER_GUIDE.md](USER_GUIDE.md), [ADMIN_GUIDE.md](ADMIN_GUIDE.md) | Yes |
| Configuration / environment ownership documented | [OWNERSHIP.md](OWNERSHIP.md) (apps, GitHub, Clerk, databases, access) | Yes |
| Deployment / update steps documented | [DEPLOYMENT.md](DEPLOYMENT.md) (deploy, config vars, migrations) | Yes |
| Recovery / rollback approach documented | [DEPLOYMENT.md §Rollback](DEPLOYMENT.md#rollback) and §Database recovery | Yes |
| User quick guide available | [USER_GUIDE.md](USER_GUIDE.md) | Yes |
| Administrator quick guide available | [ADMIN_GUIDE.md](ADMIN_GUIDE.md) | Yes |
| User and Administrator training conducted | Guides written; a formal training event has not been held yet | No |
| Support / contact path communicated | [SUPPORT.md §Contact path](SUPPORT.md#contact-path) | Yes |
| Known issues and next steps provided | [SUPPORT.md §Known issues and next steps](SUPPORT.md#known-issues-and-next-steps) | Yes |
| Repository and board access / ownership clarified | [OWNERSHIP.md](OWNERSHIP.md) (org, repo, board, Heroku transfer status) | Yes |

## Notes

- Both deployments currently return HTTP 200. Production and staging each run
  their own Heroku Postgres addon.
- Heroku **app** ownership is mid-transfer to Hudson; the `pts` **pipeline**
  cannot be transferred to a personal account and must be recreated or moved to
  a Heroku team. Tracked in [SUPPORT.md](SUPPORT.md).
- The only open checklist item is training (#9), which requires an actual
  walkthrough with members and officers rather than documentation.
