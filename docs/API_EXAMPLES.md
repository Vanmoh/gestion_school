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
