# UI Conformity Guide

## Goal
Keep visual consistency across academic pages and avoid style drift.

## Source Of Truth
Use this file for imports module visual tokens:
- frontend/gestion_school_app/lib/core/theme/academic_imports_ui_reference.dart

## Mandatory Rules
1. Do not hardcode panel colors for academic imports pages.
2. Use `AcademicImportsUiReference.panelBackground(...)` and `AcademicImportsUiReference.panelShape(...)` for import surfaces.
3. Use `AcademicImportsUiReference.importActionStyle(...)` for any "Imports academiques" action button.
4. Use `AcademicImportsUiReference.metricBackground(...)` for preview summary badges.
5. Keep spacing consistent with `AcademicImportsUiReference.pagePadding`.

## Covered Pages
- frontend/gestion_school_app/lib/features/imports/presentation/academic_imports_page.dart
- frontend/gestion_school_app/lib/features/students/presentation/students_page.dart
- frontend/gestion_school_app/lib/features/grades/presentation/grades_page.dart
- frontend/gestion_school_app/lib/features/exams/presentation/exams_page.dart
- frontend/gestion_school_app/lib/features/timetable/presentation/timetable_page.dart

## Review Checklist
- Import action button has same style on all pages.
- Disabled state is visible and readable.
- Header and helper text contrast is readable.
- Preview metric cards follow token colors.
- No new hardcoded colors were introduced for imports components.
