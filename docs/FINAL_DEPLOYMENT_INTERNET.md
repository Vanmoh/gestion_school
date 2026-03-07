# Mise en place finale (Supabase + Render) — accès internet sans PC allumé

Objectif: mobile/web/desktop fonctionnent en 4G/5G sans tunnel et sans machine locale allumée.

## 1) État déjà validé

- Connexion Supabase PostgreSQL OK (pooler IPv4)
- Migrations Django appliquées sur Supabase
- Seed de données appliqué (`seed_demo_data`)

Comptes seedés:

- `superadmin / Admin@12345`
- `directeur / Password@123`

## 2) Déployer sur Render (Blueprint)

Le blueprint est prêt dans `render.yaml` et crée:

- `gestion-school-api` (Django API)
- `gestion-school-worker` (Celery worker)
- `gestion-school-beat` (Celery beat)
- `gestion-school-redis` (Redis)
- `gestion-school-web` (Flutter Web)
- `gestion-school-downloads` (page de téléchargement APK/Desktop)

Étapes:

1. Push le projet sur GitHub.
2. Render → **New +** → **Blueprint** → sélectionner le repo.
3. Sur `gestion-school-api`, définir:
   - `DATABASE_URL=postgresql://postgres.<project-ref>:<DB_PASSWORD_ENCODED>@aws-1-eu-west-1.pooler.supabase.com:5432/postgres?sslmode=require`
   - `SECRET_KEY=<clé forte>`
4. Sur `gestion-school-worker` et `gestion-school-beat`, définir aussi:
   - `DATABASE_URL`
   - `SECRET_KEY`
5. Laisser Render déployer tous les services.

## 3) Vérifier API publique

Tester l'URL réelle affichée par Render (External URL du service `gestion-school-api`):

```bash
curl -I https://<api-render>/api/docs/
curl -I https://<api-render>/api/auth/login/
```

Attendu:

- `/api/docs/` → `200`
- `/api/auth/login/` en GET → `405` (normal)

## Déploiement Web Service Python (alternative rapide)

Si tu déploies un service Render en mode **Python** (et non Docker):

- Root Directory: `backend`
- Build Command: `pip install -r requirements.render.txt`
- Start Command: `sh start_render.sh`

Le fichier `requirements.render.txt` exclut `mysqlclient` (inutile en Supabase/PostgreSQL) pour éviter les erreurs de build cloud.
Le script `start_render.sh` exécute migration + collectstatic + gunicorn.

## 4) Build clients cloud

```bash
cd /home/van/Documents/gestion_school
./build_cloud_clients.sh --api-url=https://<api-render>/api --targets=apk,web,linux
```

## 5) Publier les téléchargements APK/Desktop

```bash
cd /home/van/Documents/gestion_school
./publish_downloads_artifacts.sh
```

Puis commit/push pour redéployer `gestion-school-downloads`.

Liens publics:

- APK: `https://<downloads-render>/app-release.apk`
- Desktop Linux: `https://<downloads-render>/gestion_school_desktop_linux.tar.gz`

## 6) Configuration mobile

Sur l'écran de connexion:

1. Ouvrir **Configuration API**
2. Saisir `https://<api-render>/api`
3. Tester connexion API

Si test OK, l'application fonctionne en données mobiles sans même réseau local.
