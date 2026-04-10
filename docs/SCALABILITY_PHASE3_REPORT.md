# Scalability Phase 3 Report

## Scope Delivered

1. Real server-side pagination with next/previous controls in:
- Users
- Payments
- Students

2. Students endpoint scaling improvements:
- Additional server-side filters/search/order coverage
- Additional indexes for common filtering patterns

3. Profiling strategy and before/after evidence:
- API before/after baseline from previous benchmark runs
- Flutter `--profile` run procedure documented for device capture

## API Before/After (Measured)

Baseline and optimized values below come from the benchmark workflow already executed in this project (`profile_api.sh` + repeated endpoint timing):

| Endpoint | Before avg (ms) | After avg (ms) | Delta |
|---|---:|---:|---:|
| `/students/` | 6221 | 367 | -94.1% |
| `/payments/` | 3624 | 33 | -99.1% |
| `/fees/` | 1481 | 14 | -99.1% |
| `/auth/users/` | 235 | 11 | -95.3% |
| `/activity-logs/` | 646 | 51 | -92.1% |

### Latest Run (24 mars 2026, 10 iterations)

Command executed:

```bash
./profile_api.sh http://127.0.0.1:8000/api <generated_jwt> 10
```

| Endpoint | Latest avg (ms) | Min (ms) | Max (ms) |
|---|---:|---:|---:|
| `/students/?page_size=80&ordering=-created_at` | 59 | 15 | 135 |
| `/payments/?page_size=80` | 53 | 15 | 109 |
| `/fees/?page_size=80` | 43 | 15 | 90 |
| `/auth/users/?page_size=80` | 32 | 9 | 190 |
| `/activity-logs/?page_size=80&ordering=-created_at` | 146 | 16 | 690 |

Note: first calls are colder (notably `activity-logs`); warmed runs are significantly lower.

## Flutter UI Before/After Table

### Latest `--profile` capture (Linux device)

Command executed:

```bash
flutter run --profile -d linux --trace-startup
```

Captured from `frontend/gestion_school_app/build/start_up_info.json`:
- `timeToFirstFrameMicros`: `87251` (87.25 ms)
- `timeToFirstFrameRasterizedMicros`: `931509` (931.51 ms)
- `timeToFrameworkInitMicros`: `84524` (84.52 ms)

| UI Surface | Before | After | Delta |
|---|---:|---:|---:|
| Startup time to first frame | N/A (not instrumented before) | 87.25 ms | N/A |
| Startup time to first frame rasterized | N/A (not instrumented before) | 931.51 ms | N/A |
| Framework init time | N/A (not instrumented before) | 84.52 ms | N/A |

Android profile run was started (`-d R58T431VAZT`) but the Gradle profile build did not finish in a reasonable window in this session, so no stable Android timing artifact was produced yet.

## Flutter Profile Strategy (`--profile`)

Use this exact run mode to capture frame timings and jank stats:

```bash
cd /home/van/Documents/gestion_school/frontend/gestion_school_app
flutter run --profile -d <device_id>
```

Recommended scenarios (same steps before and after each optimization batch):
- App startup -> login screen
- Login -> dashboard
- Open Users page, type search, navigate next/previous page
- Open Students page, apply filters, navigate next/previous page
- Open Payments page, apply search/method filter, navigate next/previous page

Capture in DevTools Performance:
- worst frame time
- average frame time
- dropped frames

## Notes

- Backend validity was checked (`manage.py check`): no issues.
- Migration coverage was checked (`makemigrations --check`): no pending changes.
- Target backend environment migration state confirms up to date (`No migrations to apply` in backend container logs).
- To rerun API timings with fresh credentials:

```bash
cd /home/van/Documents/gestion_school
./profile_api.sh http://127.0.0.1:8000/api <JWT_TOKEN> 10
```
