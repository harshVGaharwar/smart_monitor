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

## The response envelope

Every endpoint answers in the wrapper the UAT gateway uses
(`https://BBRAUAT.hdfcbankuat.com:9124/SmartAPI/…`), field for field and in the
same order, so the client reads one contract whether it points here or there:

```json
{
  "code": 0,
  "message": "Upload Successful",
  "body": null,
  "success": true,
  "data": { "rows": [] },
  "count": 0,
  "userName": null,
  "userCode": null,
  "branchName": null,
  "branchCode": null,
  "menu": null
}
```

- **`data`** is the payload, and its shape is per endpoint: `{"rows": [...]}`
  for the two read endpoints, `{"rows": [...], "inserted", "updated", "total"}`
  for `update-smartpointer`.
- **`code`** is 0 on success and non-zero on a failure; **`success`** mirrors
  it. A failure sets both, *and* an honest HTTP status — a client checking
  either one sees it.
- **`count`** is 0 on the two read endpoints even when they plainly carry rows;
  that is what the live service sends, so the client counts the rows it got
  rather than trusting it. `update-smartpointer` does set it, to the same
  number as `data.total`.
- `body`, `userName`, `userCode`, `branchName`, `branchCode` and `menu` are
  always null here. They are sent rather than dropped because a client written
  against UAT expects the keys to exist.

`lib/src/api_envelope.dart` builds it; nothing constructs a response by hand.

### Row shape

Both read endpoints return rows with these keys, in this order, shaped by
`lib/src/smart_rows.dart`:

| key | notes |
| --- | --- |
| `client_id`, `customer_name`, `account_no`, `line_no` | the natural key plus the name |
| `health_check_category`, `sub_category`, `exception_category`, `reason` | |
| `support_system`, `core_system`, `cpu`, `team` | |
| `segment`, `facility` | **null**, not `""`, when the file left them empty |
| `sr_no` | a **number**, 0 when the row is not numbered — as UAT sends it. Both models still read it written as text, so an older server keeps working |
| `maker`, `checker` | |
| `ls_srm_date` | `0001-01-01` where no date was set — .NET's `DateTime.MinValue`, which the client maps back to null |
| `status`, `imported_at` | **only on `get-smartpointer`**: they exist once a case has been stored |

`sr_no` was `facility_sr_no` before the live contract was known. That spelling
is still accepted on input, so a client that has not been rebuilt keeps
working.

## Endpoints

### `POST /api/read-excel`

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
  "code": 0,
  "message": "Upload Successful",
  "body": null,
  "success": true,
  "data": {
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
        "segment": "Retail",
        "facility": null,
        "sr_no": 1,
        "maker": "mk",
        "checker": "ck",
        "ls_srm_date": "2026-07-21"
      }
    ]
  },
  "count": 0,
  "userName": null,
  "userCode": null,
  "branchName": null,
  "branchCode": null,
  "menu": null
}
```

Values are returned **as the file stated them**. Nothing here checks CPU,
actionable team or the category columns against the master data — the client
does that, because its results table lets the user correct a cell and the row
has to move between "ready to import" and "needs attention" without another
round trip. No `id` is returned: the client numbers the rows it displays, and
a case is identified by client id / account no / line no everywhere else.

Empty cells, and the `nan` / `null` text that exports use as stand-ins for
empty, come back as **null**. Optional columns (`segment`, `facility`,
`sr_no`, `ls_srm_date`) are always present, empty when the file omits them.

**400** — the request carried no `file` part, or was not multipart.
**413** — larger than the 25 MB ceiling the client also enforces.
**422** — a file the user can fix. `message` is shown verbatim on the upload
card, so it names the missing columns rather than describing a parse failure.
**Not locally, though**: a file that cannot be read falls back to sample rows
by default — see below.

```json
{
  "code": 1,
  "message": "The file is missing required column(s): CPU, Actionable Team.",
  "body": null,
  "success": false,
  "data": null,
  "count": 0,
  "userName": null, "userCode": null,
  "branchName": null, "branchCode": null, "menu": null
}
```

#### Sample rows for an unreadable file

The upload screen needs a spreadsheet satisfying the column contract above
before it shows anything, and the first file anyone reaches for locally is
rarely one. So when the parser rejects a file, this endpoint answers **200 with
the six sample rows in `lib/src/dummy_excel_rows.dart`** instead of the 422 —
the first of them is the row UAT returns verbatim, and two carry a CPU, team or
category the master data does not recognise, so the validation report has
flagged, editable cells to show rather than a uniformly green table.

The server prints a line saying it did this. A readable file is still parsed
normally; the fallback only ever stands in for an error.

```sh
READ_EXCEL_DUMMY=0 dart_frog dev   # return the parser's real 422 instead
```

Turn it off for anything past local development — it is the same kind of switch
as `CASES_SEED`, and a deployment wants the honest error.

### `GET /api/get-smartpointer`

Every stored case, for the dashboard grid. No parameters — filtering and
search happen on the client.

**200** — `data.rows`, shaped exactly as `read-excel` returns them plus the
two fields only a stored case has, `status` and `imported_at`. An empty store
is a **success with no rows**, not an error: nobody has imported anything yet,
and the dashboard has an empty state for that.

**405** — anything but GET. (It is a GET, not a POST — it reads.)

### `POST /api/update-smartpointer`

The end of the upload flow: the rows the user approved in the results table,
written to the database. JSON, either `{"rows": [...]}` or a bare array, with
each row shaped the way `/api/read-excel` returned it. A row may carry a
`status`; one that does not leaves the stored status alone, so re-uploading a
corrected spreadsheet does not send a reviewed case back to the default.

Only rows that passed validation and survived the review are sent — the
client filters before posting, so a flagged or deleted row never arrives.

Both the request rows and the rows in the response are the same model —
`lib/src/update_request.dart` here, `lib/models/update_request.dart` in the
app. Every field is a string, every key is present, and a null means the
client is stating nothing rather than blanking the column.

**200** — `data` carries the rows **as they were stored**, and the counts:

```json
{
  "code": 0,
  "message": "Updated Successfully",
  "body": null,
  "success": true,
  "data": {
    "rows": [ { "client_id": "4943581", "…": "…", "status": "Pending with CPU" } ],
    "inserted": 2,
    "updated": 1,
    "total": 3
  },
  "count": 3,
  "userName": null, "userCode": null,
  "branchName": null, "branchCode": null, "menu": null
}
```

The rows are read back after the write rather than echoed from the request, so
they show what is actually stored: an alias resolved to its real column, a
blank normalised, and the status a row that stated none ended up keeping.

A case is identified by **client id + account no + line no** together.
Re-submitting a corrected file therefore *updates* those cases rather than
stacking duplicates alongside them, which is what makes the
fix-in-Excel-and-re-upload loop safe to repeat.

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

### Sample data

An **empty** database is seeded on startup with the cases in
`lib/src/dummy_cases.dart`, so `get-smartpointer` answers with rows on a fresh
checkout instead of sending the dashboard straight to its empty state. Their
CPU, team and category values are all ones the client's master data
recognises, so no seeded row shows up flagged.

Seeding only ever writes into an empty table: delete a sample case and it stays
deleted. To start with nothing at all:

```sh
CASES_SEED=0 dart_frog dev
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
