# Support

## Contact path

- **Primary maintainer**: Tiernan Lindauer — tiernanlind@tamu.edu
- **Incoming maintainer / Heroku owner**: Hudson — hudson.qml@tamu.edu
- **Bugs and feature requests**: open an issue on
  [FA26-CSCE431-software-engineering/PT-500](https://github.com/FA26-CSCE431-software-engineering/PT-500/issues).

Officers using the app day to day should route data questions (attendance,
points, roles) to the maintainer above.

## Training

- New members need no training: [USER_GUIDE.md](USER_GUIDE.md) covers sign-in,
  points, and RSVPs.
- New officers should read [ADMIN_GUIDE.md](ADMIN_GUIDE.md) before posting
  events or taking attendance.
- A formal walkthrough/training event for members and officers has **not** yet
  been recorded — see the checklist.

## Known issues and next steps

Known issues:

- **Heroku pipeline can't be handed to a personal account.** The `pts` pipeline
  cannot be transferred to Hudson's personal account; only the two apps can. The
  pipeline must be recreated or moved to a Heroku team.
- **App ownership transfer is pending.** `tlind-pts` and `tlind-pts-dev` are
  waiting for Hudson to accept the transfer emails.
- **No self-service officer demotion.** Removing an email from `OFFICER_EMAILS`
  does not demote anyone; it must be done in the console.
- **Signup email rule is enforced at first sign-in.** The app rejects a new
  account whose Clerk primary email is not `@tamu.edu` when the officer setting
  is on. Align Clerk's own restrictions as well.
- **Local sign-in requires `localhost`.** Clerk sets `Secure` cookies, so use
  http://localhost:3000, not `127.0.0.1`.
- **Active Storage variant warning.** Heroku logs warn that the
  `image_processing` gem is missing; harmless unless image variants are added.
- **Kamal config is unused.** `config/deploy.yml` and `.kamal/` are leftover
  Rails defaults and do not pass `OFFICER_EMAILS`; deployment is via Vercel.

Next steps:

1. Complete the deployment ownership transfer and decide the legacy Heroku pipeline's fate.
2. Add a self-service officer demotion control.
3. Record and deliver a short member/officer training event.
4. Remove or repurpose leftover template files (`config/deploy.yml`,
   `.kamal/`, `practice.txt`).
