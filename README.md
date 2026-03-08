# GESTION SCHOOL

Application complète de gestion d’établissement scolaire multi-plateforme.

## Stack
- Frontend: Flutter (Web, Android, Windows)
- Backend: Django REST Framework
- Base de données: MySQL
- Authentification: JWT
- Async/Jobs: Celery + Redis

## Structure
- `backend/` API Django + modèles métiers (incl. discipline/cantine) + reporting PDF/Excel
- `frontend/gestion_school_app/` App Flutter clean architecture
- `infra/` Docker Compose (db, redis, backend, worker, beat)
- `docs/` Documentation architecture et API

## Démarrage rapide

### 0) Bootstrap complet en une commande
```bash
./bootstrap.sh
```

Ce script lance Docker, attend les services, applique les migrations et injecte les données de démonstration.

Les scripts `bootstrap.sh`, `status.sh`, `stop.sh` et `reset.sh` tentent automatiquement `docker`, puis `sudo -n docker` si nécessaire.

### 0.1) Arrêter les services
```bash
./stop.sh
```

### 0.1.1) Vérifier l'état des services
```bash
./status.sh
```

Sortie JSON (CI/CD, monitoring):
```bash
./status.sh --json
```

### 0.2) Reset complet (destructif)
```bash
./reset.sh
```

Le reset supprime les volumes Docker (donc les données), reconstruit la stack, puis relance migrations + seed.

### 1) Backend via Docker (recommandé)
```bash
cd infra
docker compose up --build
```

Si l'accès Docker est refusé pour votre utilisateur:
```bash
cd infra
sudo docker compose up --build
```

API Swagger: `http://localhost:8000/api/docs/`

### 1.1) Initialiser la base (migrations + seed)
```bash
cd backend
/home/van/Documents/gestion_school/.venv/bin/python manage.py migrate
/home/van/Documents/gestion_school/.venv/bin/python manage.py seed_demo_data
```

Comptes de démonstration:
- superadmin / Admin@12345
- directeur / Password@123
- comptable / Password@123
- enseignant1 / Password@123
- parent1 / Password@123
- eleve1 / Password@123

### 2) Flutter
```bash
cd frontend/gestion_school_app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/api
```

Android:
```bash
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
```

Windows:
```bash
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8000/api
```

### 2.1) Build APK en une commande
Release (par défaut):
```bash
./build_apk.sh
```

Debug:
```bash
./build_apk.sh debug
```

Avec nettoyage préalable:
```bash
./build_apk.sh release --clean
```

Pour Android physique (même réseau Wi-Fi que le serveur backend):
```bash
./build_apk.sh release --api-url=http://IP_LOCALE_PC:8000/api
```

Exemple:
```bash
./build_apk.sh release --api-url=http://192.168.1.25:8000/api
```

## JWT
- Login: `POST /api/auth/login/`
- Refresh: `POST /api/auth/refresh/`
- Profil courant: `GET /api/auth/users/me/`

## Rapports
- Bulletin PDF: `GET /api/reports/bulletin/{student_id}/{academic_year_id}/{term}/`
- Reçu PDF: `GET /api/reports/receipt/{payment_id}/`
- Export Excel paiements: `GET /api/reports/payments/export-excel/`

## Sauvegarde automatique
- Commande manuelle: `python manage.py backup_db`
- Tâche planifiable via Celery Beat: `apps.common.tasks.scheduled_database_backup`

## Remarques production
- Remplacer `.env.example` par un vrai `.env` sécurisé
- Configurer un reverse proxy (Nginx) + HTTPS
- Ajouter S3/MinIO pour stockage media
- Ajouter monitoring (Prometheus/Grafana) et alerting

## Migration Supabase + déploiement cloud
- Guide complet: `docs/SUPABASE_DEPLOYMENT.md`

## Build clients vers API cloud
- Script multi-plateformes: `./build_cloud_clients.sh --api-url=https://<api-publique>/api`
- Cibles disponibles: `apk`, `web`, `linux` (option `--targets=...`)

## Blueprint Render
- Déploiement backend+worker+beat+redis: `render.yaml`
- Déploiement staging (API de test en ligne): `render.staging.yaml`
- Variables Supabase prêtes à remplir: `backend/.env.supabase.example`

## Workflow staging (test avant prod)
- Guide étape par étape: `docs/STAGING_WORKFLOW.md`
- Script one-click de promotion staging -> prod: `./promote_staging_to_main.sh`

## Dépannage rapide (Docker)
- Vérifier l'état global: `./status.sh`
- En cas d'accès refusé au socket Docker, relancer la commande avec `sudo` ou ajouter l'utilisateur au groupe `docker`.
