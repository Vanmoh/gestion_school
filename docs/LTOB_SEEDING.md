# LTOB Data Seeding & Student Matricule Documentation

## Overview

This document describes the LTOB (Lycée Technique Officiel de Bamako) data seeding system and the Student matricule generation format.

## Matricule Format

The Student matricule (ID) is auto-generated based on:
- **Establishment code** (2 chars)
- **Class code** (2-4 chars)
- **Entry year** (2 digits)
- **Entry type** (always 'E')
- **Sequence number** (4 digits, zero-padded)
- **Gender** (1 char: M/F)

### Examples

```
LT10CT24E0001M  (LTOB, 10ème CT, 2024 entry, student #1, Male)
LT10CT24E0002F  (LTOB, 10ème CT, 2024 entry, student #2, Female)
LT11CG24E0001M  (LTOB, 11ème CG, 2024 entry, student #1, Male)
```

### Normalization Rules

1. **Establishment Code**: First letters of establishment name words
   - "LTOB" → "LT"
   - "Lycée Technique" → "LT"
   - Single word → first 2 chars

2. **Class Code**: Remove "ème", "é/è/ô" accents, keep alphanumeric
   - "10ème CT" → "10CT"
   - "11ème CG" → "11CG"
   - "12ème GM" → "12GM"

3. **Entry Year**: Last 2 digits of year
   - 2024 → "24"
   - 2025 → "25"

4. **Sequence**: Incremented per establishment/class/year/gender combination
   - Prevents collisions when multiple students in same class

## Seed Command: seed_ltob_data

### Usage

```bash
python manage.py seed_ltob_data [--etablissement LTOB] [--academic-year 2024-2025]
```

### Options

- `--etablissement`: Establishment name (default: LTOB)
- `--academic-year`: Academic year (default: 2024-2025)

### What Gets Created

1. **Establishment**: 1 LTOB establishment
2. **Classes**: 5 classes
   - 10ème CT (Technical - 10th grade)
   - 11ème CG (Accounting - 11th grade)
   - 11ème GM (Mechanical - 11th grade)
   - 12ème CG (Accounting - 12th grade)
   - 12ème GM (Mechanical - 12th grade)

3. **Subjects**: 8-9 subjects per class
   - French (Français)
   - English (Anglais)
   - Mathematics (Mathématiques)
   - + specialized subjects per track

4. **Students**: 10 students per class (50 total)
   - Random Malian names
   - Birth dates: 2005-2007
   - Conduite: 15-20
   - Gender: M or F

### Data Validation

All generated data is validated:
- ✅ Birth dates are never future dates
- ✅ Birth dates handle leap years correctly
- ✅ Conduite (conduct) is between 0-20
- ✅ Matricules are unique per establishment
- ✅ Student names are properly parsed

### Example Output

```
Creating establishment: LTOB
Using academic year: 2024-2025

✓ Created classroom: 10ème CT
✓ Created classroom: 11ème CG
✓ Created classroom: 11ème GM
✓ Created classroom: 12ème CG
✓ Created classroom: 12ème GM

✓ Total classrooms: 5
✓ Total subjects created: 42
✓ Total students created: 50

============================================================
SEEDING COMPLETED SUCCESSFULLY
============================================================
Établissement: LTOB
Année académique: 2024-2025
Classes: 5
Matières: 42
Élèves: 50
============================================================
```

## Student Model

### Fields

| Field | Type | Description |
|-------|------|-------------|
| user | OneToOne | Django User |
| matricule | CharField | Auto-generated student ID |
| gender | CharField | M=Male, F=Female |
| birth_date | DateField | Date of birth |
| classroom | ForeignKey | Student's class |
| parent | ForeignKey | Parent profile |
| photo | ImageField | Student photo |
| enrollment_date | DateField | Auto-set on creation |
| is_archived | BooleanField | Soft delete flag |
| conduite | DecimalField | Conduct/behavior score (0-20) |
| etablissement | ForeignKey | School establishment |

### Validation

The Student model includes automatic validation:

```python
def clean(self):
    # Birth date cannot be in future
    if self.birth_date > date.today():
        raise ValidationError('Birth date cannot be in the future')
    
    # Conduite must be between 0 and 20
    if not (0 <= self.conduite <= 20):
        raise ValidationError('Conduite must be between 0 and 20')
```

### Save Hook

```python
def save(self, *args, **kwargs):
    # Auto-generate matricule if not set
    if not self.matricule:
        self.matricule = self._build_matricule()
    # Validate data
    self.full_clean()
    super().save(*args, **kwargs)
```

## Improvements Made

### Code Quality
- ✅ Added logging throughout seed process
- ✅ Fixed date generation edge cases (Feb 29, month boundaries)
- ✅ Optimized name parsing (split once, reuse)
- ✅ Improved error handling with IndexError catches
- ✅ Added comprehensive docstrings

### Testing
- ✅ 10+ unit tests for seed command
- ✅ 15+ unit tests for Student model
- ✅ Validation test coverage
- ✅ Edge case handling tests

### Data Integrity
- ✅ Automatic validation on save
- ✅ Birthdate future-date prevention
- ✅ Conduite range validation (0-20)
- ✅ Matricule uniqueness enforcement
- ✅ Idempotent seeding (safe to run multiple times)

## Usage Examples

### Run seed with defaults

```bash
python manage.py seed_ltob_data
```

Creates 50 students for LTOB in 2024-2025 academic year.

### Run seed with custom school

```bash
python manage.py seed_ltob_data --etablissement="My School"
```

### Run with different academic year

```bash
python manage.py seed_ltob_data --academic-year 2025-2026
```

### Run tests

```bash
# All tests
python manage.py test apps.school.tests

# Specific test class
python manage.py test apps.school.tests.test_seed_ltob_data.SeedLTOBDataCommandTest

# Specific test method
python manage.py test apps.school.tests.test_student_model.StudentModelTest.test_matricule_auto_generation
```

## Related Files

- `backend/apps/school/management/commands/seed_ltob_data.py` - Seed command
- `backend/apps/school/models.py` - Student model
- `backend/apps/school/serializers.py` - Student serializer
- `backend/apps/school/tests/test_seed_ltob_data.py` - Seed tests
- `backend/apps/school/tests/test_student_model.py` - Model tests
