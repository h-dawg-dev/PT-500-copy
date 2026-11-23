# Event import and CSV reports

Signed-in officers can open **Event import and CSV reports** from the officer dashboard
or event list, at `/officer/csv_transfer`. Members and anonymous visitors cannot
upload events or download reports.

## Import the GetInvolved event dashboard export

1. Download the event export from GetInvolved as an Excel `.xlsx` workbook.
2. Open **Event import and CSV reports**, choose that workbook and click **Import events**.
   No Excel save/conversion step is needed. Keep its one event worksheet and original headers.
   Existing CSV UTF-8 exports are also accepted.
3. Follow **Review events** and set the intended points and category on each
   imported event before marking attendance.

The importer supports the shape of the supplied GetInvolved export:

| GetInvolved column | App behavior |
| --- | --- |
| Reference | Unique source ID, such as `EVN-26994`; repeat imports skip existing IDs |
| Type | Must be `Event` |
| Title | Event title; HTML entities are decoded |
| Starts / Ends | Central time, e.g. `Sep 22, 2026 7:00 pm`; both are required and end cannot precede start |
| Location / Location Detail | Combined with ` - `; detail alone works when location is blank |
| Marketing Blurb | Event notes; HTML entities are decoded |
| Organization / Status / Visibility / Event Planner | Retained as source metadata |

`Reference`, `Type`, `Title`, `Starts` and `Ends` are required headers. The other
seven columns may be omitted. Column order may change; header spelling must stay
the same. Excel workbooks must have exactly one event worksheet, with headers in
the first row. Text dates from GetInvolved and Excel date/time cells are supported.
Blank cells retain their column positions. Legacy `.xls` files are not supported.
CSV UTF-8 files with or without a byte-order mark work, including quoted commas and
multiline notes. Uploads are limited to 2 MB and 2,000 rows; Excel workbook contents
must expand to no more than 20 MB. The importer shows up to 20 row errors per attempt.
Row numbers include the header and refer to worksheet rows or CSV records, rather
than physical lines inside multiline CSV fields.

**New events have 1 point and the general category.** This export has no points
or attendance, so neither is inferred. The importing officer becomes the local
creator; Event Planner stays source metadata. The existing event model assigns
the term covering the start date. Dates outside all configured terms remain
unassigned and appear in all-time reports.

All source statuses are imported, including Initiated, Submitted and Approved.
Status and Visibility are metadata; they do not restrict visibility in this app.
Imported events appear on the existing member event board. Select the intended
rows in the source worksheet before uploading if only some should appear.

Import is atomic: invalid new rows, duplicate references within the file,
an unreadable workbook/CSV or a database conflict prevent all new records from being saved.
Existing references are skipped without updating their source metadata, title,
dates, category, points or attendance. A mixed file can add new references while
skipping existing ones. Retry after a concurrent import conflict.

The reference matches only previously imported events. A manually created event
with the same title has no GetInvolved reference and is not matched automatically.
Review the board before the first import to avoid adding a second copy of such an
event. Deleting an imported event also deletes its attendance under the existing
event behavior; importing that reference again creates a new one-point event.

If your sign-in expires during an upload, authentication refreshes using a GET
instead of forwarding the upload POST to Clerk. The page then asks you to choose
the file and import again; no events were imported by the interrupted request.

## Download reports

Choose a report and a term, or **All time**, then click **Download CSV**. The
default is the current term, or all time if no term covers today. Each file has a
descriptive date-stamped filename, UTF-8 byte-order mark for Excel and CRLF record
separators. Text starting like a spreadsheet formula is prefixed with an
apostrophe in the CSV; stored app values do not change.

| Report | Contents |
| --- | --- |
| Events | Event IDs, source references, title, dates with Central UTC offset, location, notes, category, points, term, attendance/RSVP counts and source metadata |
| Attendance | One row per actual attendance, officers included: event, term, category, points awarded (the current event points for a member, 0 for an officer), name/email, role, recording officer and recorded timestamp |
| Members and points | Every member, including those with no attendance; role, attendance count, net point adjustments, total and category points (adjustments included), required points and requirement status. Officers are not listed |

Reports use the same current event point values as member charts; they are not
historical snapshots of credit at check-in time. RSVPs never award points.
Officer point adjustments count in the term they were made for, the same as on
member charts.
Officers are outside the points system: their attendance is recorded and shown
in the attendance report, but it is worth 0 points and they never appear in the
members and points report, however often it is regenerated. This follows each
person's current role, so a member who becomes an officer leaves the points
report and their earlier attendance shows 0 points.
Term reports include events assigned to that term. All-time reports include
unassigned events and evaluate requirements against the app defaults (7 total,
1 professional, 1 social). With no events, event/attendance files still contain
headers. Names and emails are officer-only data; responses use `Cache-Control:
no-store`.

These reports are app reports, not a GetInvolved re-import format. Only the
original GetInvolved event headers/date format are accepted by the importer.
This feature does not import attendance, enroll members or export intake form
responses.

## Developer notes and verification

Run `bundle install` and `bin/rails db:migrate` before using the feature. Migration
`20261001120000` adds nullable `events.getinvolved_reference`, a unique database
index, and `events.getinvolved_data` JSONB with an empty-object default. Existing
events need no backfill. Rolling this migration back removes import identity and
metadata; restoring it does not recover those values.

Routes delegate to `Officer::CsvTransfersController`, protected by the existing
officer base controller. `GetinvolvedEventImport` validates a bounded file before
the transaction; the database index guards duplicate references across requests.
`OfficerCsvExport` allowlists three reports, preloads event/attendance associations
and computes member totals with grouped queries. Downloads are generated in
memory, which is appropriate for the society's current dataset; larger report
volumes would need streaming or background generation.

Focused coverage is in `spec/services/getinvolved_event_import_spec.rb`,
`spec/services/officer_csv_export_spec.rb` and
`spec/requests/officer/csv_transfers_spec.rb`. Import examples preserve the supplied
worksheet's headers, dates, statuses and empty location cases while replacing
planner names and simplifying titles. Checks cover Central time across daylight
saving offsets, HTML entities, repeated imports preserving edits/attendance,
direct Excel uploads, invalid workbooks, upload/expanded-size limits and transaction rollback, accurate points vs RSVPs, formula-safe
quoting, period selection and officer-only multipart upload/download.
