# Improvement Roadmap (3 Sprints)

## Sprint 1 - Security + Baseline Quality (1 week)

### Goals
- Remove risky production defaults.
- Add basic automated quality gates.
- Stabilize bootstrap and runtime checks.

### Scope
- Backend config hardening in `backend/config/settings.py`.
- Add CI checks for backend (`manage.py check`, tests) and frontend (`flutter analyze`, tests).
- Add deterministic health output in `status.sh`.

### Deliverables
- Secure production-ready settings defaults.
- CI workflow running on pull requests.
- Repeatable smoke command list for release.

### Acceptance Criteria
- Production cannot start with weak defaults (`SECRET_KEY`, `ALLOWED_HOSTS`, permissive CORS).
- CI fails on lint/test failure.
- Bootstrap + status scripts return clear pass/fail signals.

## Sprint 2 - Students/Teachers UI Modularization (1-2 weeks)

### Goals
- Reduce large-page complexity.
- Keep UX consistent across modules.
- Improve maintainability and testability.

### Scope
- Split `students_page.dart` into sub-widgets:
  - actions header
  - students table
  - dossier panel
  - finance section
- Apply same panel grammar to teachers module.
- Add widget tests for key interactions.

### Deliverables
- Smaller files and clearer ownership.
- Shared UI action panel pattern.
- Regression tests for top workflows.

### Acceptance Criteria
- Main page files reduced in size and complexity.
- No duplicated actions in student and teacher modules.
- Widget tests cover critical create/edit flows.

## Sprint 3 - Deployment Reliability + Observability (1 week)

### Goals
- Reduce deployment/build flakiness.
- Improve diagnosis speed when incidents happen.

### Scope
- Add retry logic for Docker image metadata pulls in scripts.
- Improve deployment scripts with explicit error sections.
- Add app/service health checks and structured logs.

### Deliverables
- More resilient deployment pipeline.
- Faster troubleshooting with actionable status output.

### Acceptance Criteria
- Fewer transient deployment failures.
- Clear runbooks and status outputs for operators.
- Health checks validated before release promotion.

## Priority Order
1. Sprint 1 (must do first)
2. Sprint 2
3. Sprint 3
