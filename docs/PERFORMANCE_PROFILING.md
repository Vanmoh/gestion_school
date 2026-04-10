# Performance Profiling: Before/After

## 1) Backend API profiling (quantitative)

Use the helper script to benchmark heavy endpoints:

```bash
cd /home/van/Documents/gestion_school
./profile_api.sh http://127.0.0.1:8000/api <JWT_TOKEN> 10
```

Tracked endpoints:
- `/students/`
- `/payments/`
- `/fees/`
- `/auth/users/`
- `/activity-logs/`

Output gives per-run and aggregate:
- `avg` (primary KPI)
- `min`
- `max`

### Header-level profiling

When `ENABLE_PROFILING_HEADERS=true` (or `DEBUG=True`), API responses include:
- `X-Response-Time-ms`
- `X-Query-Count` (debug mode)

Quick check:

```bash
curl -I -H "Authorization: Bearer <JWT_TOKEN>" \
  "http://127.0.0.1:8000/api/students/?page_size=50"
```

## 2) Flutter/web profiling

### Startup/profile run

```bash
cd /home/van/Documents/gestion_school/frontend/gestion_school_app
flutter run -d web-server --profile --web-hostname=127.0.0.1 --web-port=8080 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```

### Measure frame smoothness

1. Open DevTools performance timeline.
2. Record interactions:
- opening landing page,
- login,
- users/students/payments pages,
- activity logs search/filter.
3. Compare before/after:
- dropped frames,
- longest frame time,
- CPU busy blocks.

## 3) Baseline protocol

For each change set:

1. Run backend benchmark script (10 iterations).
2. Capture Flutter timeline for the same scenario.
3. Store results in a table:
- endpoint/page,
- before avg ms,
- after avg ms,
- delta %.

## 4) Acceptance targets

Suggested targets (local env):
- List endpoints avg: `< 300 ms`
- Activity logs filtered avg: `< 400 ms`
- No long jank frame above `100 ms` during page transitions.
