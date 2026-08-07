# smart_monitor backend

Dart Frog server for the SMART app. It exists because the Flutter client no
longer opens spreadsheets itself — the upload screen posts the file here and
renders whatever comes back.

## Running

```sh
cd backend
dart_frog dev          # http://localhost:8080, hot reload
```

That is the address `AppConstants.apiBaseUrl` defaults to
(`http://localhost:8080/api`), so `flutter run -d chrome` needs no extra flags
against a local server.

For a production build:

```sh
dart_frog build
dart build/bin/server.dart
```

## Endpoints

### `POST /api/cases/upload`

Multipart, with two parts:

| part | kind | value |
| --- | --- | --- |
| `file` | file | the workbook itself |
| `fileType` | field | its extension — `xlsx` or `csv`, dot and case ignored |

`fileType` is what picks the reader, so a browser upload with an unhelpful
filename still parses. When it is absent the extension of the uploaded
filename is used instead, which keeps plain `curl` posts working.

Accepts `.xlsx` and `.csv`. `.xls` is rejected with a message asking for a
re-save, since the old binary format is not a zip archive and cannot be
opened by the reader here.

**200** — every data row in the file, clean or not:

```json
{
  "count": 2,
  "rows": [
    {
      "client_id": "4943581",
      "customer_name": "ACME",
      "account_no": "50200031339584",
      "line_no": "5",
      "health_check_category": "CAM Expiry Health Check",
      "sub_category": "Sub",
      "support_system": "LMM",
      "core_system": "FC",
      "exception_category": "Exception",
      "reason": "Renewal pending",
      "cpu": "Mumbai",
      "team": "Cam Renewal Team",
      "maker": "mk",
      "checker": "ck",
      "segment": "Retail",
      "facility_sr_no": "1",
      "ls_srm_date": "2026-07-21"
    }
  ]
}
```

Values are returned **as the file stated them**. Nothing here checks CPU,
actionable team or the category columns against the master data — the client
does that, because its results table lets the user correct a cell and the row
has to move between "ready to import" and "needs attention" without another
round trip. No `id` is returned: the client numbers the rows it displays, and
a case is identified by client id / account no / line no everywhere else.

Empty cells, and the `nan` / `null` text that exports use as stand-ins for
empty, come back as `""`. Optional columns (`segment`, `facility_sr_no`,
`ls_srm_date`) are always present, blank when the file omits them.

**400** — the request carried no `file` part, or was not multipart.
**413** — larger than the 25 MB ceiling the client also enforces.
**422** — a file the user can fix. `message` is shown verbatim on the upload
card, so it names the missing columns rather than describing a parse failure.

```json
{ "message": "The file is missing required column(s): CPU, Actionable Team." }
```

### `POST /api/cases/import`

The end of the upload flow: the rows the user approved in the results table,
written to the database. JSON, either `{"rows": [...]}` or a bare array, with
each row shaped the way `/upload` returned it.

Only rows that passed validation and survived the review are sent — the
client filters before posting, so a flagged or deleted row never arrives.

**200** — what the submit did:

```json
{ "inserted": 11, "updated": 3, "total": 14 }
```

A case is identified by **client id + account no + line no** together.
Re-submitting a corrected file therefore *updates* those cases rather than
stacking duplicates alongside them, which is what makes the
fix-in-Excel-and-re-upload loop safe to repeat. `inserted` counts rows that
were new, `updated` counts rows that overwrote an existing case.

**400** — no JSON body, or no rows in it.
**422** — one or more rows have no client id / account no / line no. Such a
row cannot be stored without colliding with every other one missing a key, so
**the whole submit is refused and nothing is written** rather than partly
saved.

## Storage

SQLite, at `cases.db` beside the server — override with the `CASES_DB`
environment variable. It needs no second service to run alongside this one and
the file is trivial to inspect (`sqlite3 cases.db`) or back up.

```sh
CASES_DB=/var/lib/smart/cases.db dart build/bin/server.dart
```

`lib/src/cases_repository.dart` owns the schema and the upsert. Every column
is `TEXT`: the upload has no types worth preserving, and storing an account
number as a number risks rounding a 14-digit value into a double. Each import
is one transaction, so a failure part-way leaves the table as it was rather
than half-written.

The `cases` table is keyed on client id + account no + line no, with no
surrogate id, and carries a `status` column defaulting to `Pending` and an
`imported_at` timestamp, so the dashboard has something to read once it moves
off `MockData`.

## Reading files

`lib/src/` holds the parsing that used to live in the Flutter app:

- `cases_file_parser.dart` — header matching (including aliases such as
  `Unit` → `CPU`), then a row per data line. The header is found by looking
  for the first row naming a column it recognises, so a title or report-date
  row above it does not derail the read.
- `xlsx_reader.dart` — a minimal .xlsx reader over `archive` + `xml`, rather
  than a workbook library, because real exports vary in ways those libraries
  assert on (notably relationship targets written as absolute paths).
- `csv_reader.dart` — RFC 4180, with the delimiter sniffed from the header so
  semicolon-separated exports work too.

Both readers are hand-rolled partly to keep the server off a package that
pins a Dart SDK floor — the `csv` package raised its floor to `^3.10.1` in
7.0.0, which is what broke the app's build on older toolchains.

## CORS

`routes/_middleware.dart` answers the preflight and allows any origin, which
is what makes the Flutter web dev server (a different port) able to reach
this at all. **Tighten `Access-Control-Allow-Origin` to the deployed origin
before this goes anywhere real.**

## Tests

```sh
dart test
```
