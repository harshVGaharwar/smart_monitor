# SMART

**Self Monitoring And Reconciliation Tracker** — an internal Flutter web application for tracking, verifying and resolving reconciliation breaks across processing units.

## Run

```bash
flutter pub get
flutter run -d chrome
```

## Structure

- `lib/theme/` — design system (colors, theme)
- `lib/models/` — data models
- `lib/data/` — mock data source
- `lib/pages/` — login & dashboard screens
- `lib/widgets/` — sidebar, stat cards, status badge, cases table


CASES_DB=/tmp/scratch.db dart_frog dev

mv cases.db.bak cases.db


──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
❯ '/var/folders/sy/96sr7_pd2knb97z09409zkx40000gn/T/TemporaryItems/NSIRD_screencaptureui_ZwPfxR/Screenshot 2026-08-13 at
  10.58.22 AM.png' message count , last message /getmsartpointer jo api se mil raha hai usko show karo idhar

  2  ✅ create api  /getMasterData  — done
         GET, no params. data { cpus, teams, exceptionCategories,
         healthCheckCategories, reassignReasons } — see docs/API.md §10