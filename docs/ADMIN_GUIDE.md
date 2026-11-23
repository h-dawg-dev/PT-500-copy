# Administrator Guide (Officers)

For officers who post events, take attendance, and manage roles.

## Becoming an officer

The app reads the `OFFICER_EMAILS` config var (comma-separated, case-insensitive)
from the deployment environment. A matching account is promoted to `officer`
when it signs in, and existing members are promoted on their next sign-in.

Set it in the Vercel project (**Project -> Settings -> Environment Variables**),
or in `.env` for local development:

```text
OFFICER_EMAILS=a@tamu.edu,b@tamu.edu
```

Promote immediately from **Manage admins** in the app. If you have Rails console
access for the deployment, you can also run:

```ruby
User.find_by(email: "a@tamu.edu").update!(role: :officer)
```

Officers are **never auto-demoted**. To revoke access, first remove the email from
`OFFICER_EMAILS` in the relevant Vercel project, keeping the other officer emails.
Then demote the saved account with Rails console/database access for that
deployment. There is not yet a demote button in the app.

```ruby
User.find_by(email: "a@tamu.edu").update!(role: :member)
```

Both steps are required: demotion alone is undone on the next sign-in while the
email remains allowlisted; removing the email alone leaves the existing officer
role in place. Confirm a returning sign-in is still a member and cannot open
`/officer`. Apply the change separately to dev and production if the account has
access to both.

## Officer dashboard

Open **Officer tools** in the header, or go to `/officer`. From here you can see
the next event and open events, member records and point adjustments,
intake forms, terms, society settings, and CSV reports. Only signed-in officers
can reach any `/officer` page; everyone else is redirected with
"That area is for officers."

## New member signups

Open **Society settings** from the officer dashboard. Turn on
**Require a @tamu.edu email address for new signups** to stop new accounts that
use another domain. The app checks the primary email from Clerk when a new
account first signs in and shows a clear sign-out page instead of creating a
member record.

- Existing accounts are never removed, demoted, or blocked by this switch, even
  if their email is outside `tamu.edu`.
- Addresses listed in `OFFICER_EMAILS` are exempt, so an officer or advisor with
  another domain can still complete a first sign-in and get the officer role.
- Turning the switch off again lets new accounts use any valid email.
- Keep Clerk's own sign-up restrictions aligned when possible. The app-side rule
  still catches accounts created directly in Clerk.

## Posting an event

1. Click **Post an event** (`/officer/events/new`).
2. Fill in the fields:
   - **Title** (required)
   - **Location**
   - **Starts at** / **Ends at** (end must be after start)
   - **Points** (integer, 0 or more, up to the database integer limit)
   - **Category** — `general`, `professional`, or `social`
   - **Notes**
3. Save. The event appears on the member event board.

The term (semester) is assigned automatically from the start time, based on the
`Term` whose date range covers it.

Edit or delete an event from its officer page. Point/category edits change
existing members' totals, and deletion also removes its attendance and credit.
Review the attendance and points reports before changing an attended event.

## Taking attendance

1. Open the event from `/officer/events`.
2. On the roster (`/officer/events/:id`), find the member — use the search box.
3. Toggle them **present** or **not present**. Each attendance records the
   officer who marked it.

Marking a member present is what awards that event's points to their chart.

Officers are on the roster too and can be marked present, but they are outside
the points system: an officer's attendance is recorded and earns 0 points. Their
roster row is labelled **no points**.

## Adjusting a member's points

Use an adjustment to correct a mistake, such as a member who attended but was
never checked in.

1. Open **Member records and point adjustments** from the officer dashboard
   (`/officer/members`) and click the member's name. The list shows everyone's
   points for the current term; press `/` to search by name or email.
2. Under **Adjust points**, enter a whole-number **Amount**: a positive number
   adds points and a negative number, such as `-2`, subtracts them.
3. Choose a **Category** (general, professional, or social) and give a
   **Reason**.
4. Click **Save adjustment**. The member's total, category progress, and points
   history update immediately, on their record and on their own home page.

- An adjustment counts toward the **current term** only. Other terms and other
  members are not changed.
- A blank, zero, or non-whole amount, a missing category, or a blank reason is
  rejected with a message saying what to fix, and nothing is saved.
- A subtraction cannot take a member's points in that category below zero for
  the term.
- Officers are outside the points system: their records have no adjustment
  form and they cannot be given points. Members cannot open member records.
- If no term covers today, adjustments are unavailable until the term dates are
  set.
- Each adjustment is kept with the officer who made it and when. There is no
  edit or delete; to undo one, save the opposite amount with a reason.
- The member sees a pop-up with the amount, category, reason and date the next
  time they open the app, so write the reason for the member to read.
- As with attendance, a member who becomes an officer stops earning from their
  adjustments.

## Recording member dues

Members pay dues outside the app. The **Dues** link in the header (shown to
members only) opens the society's FlyWire payment page in a new tab. The app never
sees or stores card details. After a member pays, an officer records it:

1. Open **Member records and point adjustments** from the officer dashboard
   (`/officer/members`) and click the member's name.
2. Under **Dues**, click **Mark dues paid**. The section changes to
   "Dues paid for" the current term, and the member's home page shows it as paid
   right away.
3. To fix a mistake, click **Undo dues payment** and confirm. The member goes back
   to unpaid.

- Any officer can record or undo dues.
- Dues are tracked **per term**, like points. A new term starts with everyone
  unpaid, so there is nothing to reset, and earlier terms' payments are kept.
- Recording or undoing dues changes only that member's dues for the current term.
  Their points, attendance, and other members are not affected.
- Officers are outside the dues system, just as with points: their records say
  "Officers do not pay dues" and have no button. Members cannot open member records,
  so they cannot change their own or anyone else's dues.
- The app stores which officer recorded each payment.
- If no term covers today, dues cannot be recorded until the term dates are set.
- If the semester changes while a record is open, the click is refused with "The
  semester changed or no semester is active. Nothing was changed." Reload the
  record and try again.
- If a member becomes an officer, they show as not paid. Any earlier payment record
  is kept but ignored.

### Setting the payment link

The **Dues** link uses the `DUES_PAYMENT_URL` config var, set the same way as
`OFFICER_EMAILS` (in the Vercel project, or in `.env` for local development):

```text
DUES_PAYMENT_URL=https://...
```

Use the FlyWire address the customer approved. If the variable is missing or does
not start with `https://`, the **Dues** link is hidden for everyone, so check it
after each new deployment.

## Event import and CSV reports

Open **Event import and CSV reports** from the dashboard or event list. Download event,
attendance or member-points reports for one term or all time. To import a
GetInvolved events, upload the **Excel (.xlsx)** export directly, keeping its
one event worksheet and original headers. CSV UTF-8 also works. Imported events begin at 1 point in the general
category; review them before recording attendance. Repeat source references are
skipped, preserving local edits. See [CSV_TRANSFERS.md](CSV_TRANSFERS.md) for the
column mapping, validation rules and report meanings.

## Terms (semesters)

Open **Terms and semesters** from the officer dashboard. Members' points are
scoped to the current term, so keep a term whose dates cover today.

1. Click **Add a term** and fill in the name, start and end dates, and the point
   requirements.
2. Save. Existing events whose start dates fall inside the new range are
   assigned automatically.
3. Use **Edit** to change dates or requirements. Changing dates reassigns events
   in the old and new ranges; review member totals before and after the change.

Terms cannot overlap, including a shared boundary date. Existing attendance is
preserved when term dates change. If no term covers today, members see
**Current term unavailable** and their all-time check-in history. Past points do
not satisfy an unconfigured semester.

New databases loaded from the schema need `rails db:seed` for reference terms;
repeating seeds preserves named terms already configured by an administrator.
Add future terms before their start date.

## Intake form responses

Open **Member intake forms** from the officer dashboard. The table shows each
submission newest first, with the member's name, email, class standing, optional
background answers, and email opt-in. The same answers also appear on the
member's record, alongside their major and T-shirt size.

Responses are stored in `questionnaire_responses` if you need a console backup:

```ruby
QuestionnaireResponse.order(created_at: :desc).limit(20)
```

## Support

See [SUPPORT.md](SUPPORT.md).