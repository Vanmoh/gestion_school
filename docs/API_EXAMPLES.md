# Exemples API

## Login JWT
```http
POST /api/auth/login/
Content-Type: application/json

{
  "username": "admin",
  "password": "password123"
}
```

## Création élève
```http
POST /api/students/
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "user": 12,
  "classroom": 3,
  "parent": 7,
  "birth_date": "2012-09-14",
  "is_archived": false
}
```

## Saisie note
```http
POST /api/grades/
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "student": 5,
  "subject": 2,
  "classroom": 3,
  "academic_year": 1,
  "term": "T1",
  "value": 14.5
}
```

## Recalcul classement
```http
POST /api/grades/recalculate_ranking/
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "classroom": 3,
  "academic_year": 1,
  "term": "T1"
}
```

## Dashboard financier
```http
GET /api/dashboard/
Authorization: Bearer <access_token>
```

## Import élèves par classe (CSV/XLSX)
Le fichier doit contenir au minimum: `matricule`, `first_name`, `last_name`.
Colonnes optionnelles: `username`, `email`, `phone`, `birth_date`.

Prévisualisation:
```http
POST /api/students/import-by-class/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
confirm=false
file=<eleves_classe.xlsx>
```

Validation finale:
```http
POST /api/students/import-by-class/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
confirm=true
file=<eleves_classe.xlsx>
```

## Import notes de contrôles par classe (CSV/XLSX)
Colonnes recommandées: `student_matricule`, `subject_code` (ou `subject_name`), `value`.

Prévisualisation:
```http
POST /api/grades/import-controls/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
academic_year_id=1
term=T1
confirm=false
file=<notes_controles.csv>
```

Validation finale:
```http
POST /api/grades/import-controls/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
academic_year_id=1
term=T1
confirm=true
file=<notes_controles.csv>
```

## Import notes d'examens par classe (CSV/XLSX)
Colonnes recommandées: `student_matricule`, `subject_code` (ou `subject_name`), `score`.

Prévisualisation:
```http
POST /api/exam-results/import-exams/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
session_id=4
confirm=false
file=<notes_examens.xlsx>
```

Validation finale:
```http
POST /api/exam-results/import-exams/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
session_id=4
confirm=true
file=<notes_examens.xlsx>
```

## Import emploi du temps par classe (CSV/XLSX)
Colonnes recommandées: `day_of_week` (MON..SAT), `start_time`, `end_time`, `subject_code` (ou `subject_name`), `room`.

Prévisualisation:
```http
POST /api/teacher-schedule-slots/import-by-class/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
confirm=false
file=<edt_classe.xlsx>
```

Validation finale (avec confirmation des conflits de classe):
```http
POST /api/teacher-schedule-slots/import-by-class/
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

classroom_id=3
confirm=true
confirm_conflicts=true
file=<edt_classe.xlsx>
```

