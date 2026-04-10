# Migration Supabase + Accès 24/7 (mobile/web/desktop sans PC local)

## Architecture cible

Pour que l'application fonctionne partout et tout le temps:

1. **Base de données**: PostgreSQL Supabase (cloud)
2. **API backend**: Django hébergé sur un service cloud (Render/Railway/Fly)
3. **Clients** (APK/Web/Desktop): pointent vers l'URL publique de l'API

> Important: l'URL Supabase (`https://...supabase.co`) et les clés `publishable/anon` ne remplacent pas directement l'API Django actuelle.
> Le backend Django doit rester en ligne sur une URL publique.

---

## 1) Infos Supabase nécessaires

Depuis **Supabase > Project Settings > Database**, récupère:

- le mot de passe DB
- l'URL **Session Pooler** (recommandé en réseau IPv4)
- l'URL **Direct Connection** (option de secours, souvent IPv6-only)

Format recommandé (Session Pooler):

`postgresql://postgres.<project-ref>:<DB_PASSWORD>@<pooler-host>:5432/postgres?sslmode=require`

Format alternatif (Direct):

`postgresql://postgres:<DB_PASSWORD>@db.<project-ref>.supabase.co:5432/postgres?sslmode=require`

### Projet actuel

- Project URL: `https://ztwrwmufrbzlrtgnwlyt.supabase.co`
- Project ref: `ztwrwmufrbzlrtgnwlyt`

URL DB recommandée pour ce projet:

`postgresql://postgres.ztwrwmufrbzlrtgnwlyt:<DB_PASSWORD>@aws-1-eu-west-1.pooler.supabase.com:5432/postgres?sslmode=require`

> Les clés Supabase `publishable` / `anon` ne remplacent pas `DATABASE_URL` dans Django.

---

## 2) Variables d'environnement backend

Base-toi sur:

- `backend/.env.supabase.example`

Tu peux aussi générer un bloc prêt à coller dans Render:

`./prepare_supabase_render_env.sh --db-password='<DB_PASSWORD>' --api-domain='gestion-school-jkzf.onrender.com' --web-domain='gestion-school-web.onrender.com' --output-file='backend/.env.render.local'`

Variables essentielles:

- `DEBUG=False`
- `SECRET_KEY=<clé forte>`
- `ALLOWED_HOSTS=<domaine-api>`
- `DATABASE_URL=<url postgres supabase complète>`
- `DB_SSL_REQUIRE=True`
- `DB_CONN_MAX_AGE=600`
- `CORS_ALLOW_ALL_ORIGINS=False`
- `CORS_ALLOWED_ORIGINS=<domaine(s) frontend>`
- `CSRF_TRUSTED_ORIGINS=https://<domaine-api>`
- `CELERY_BROKER_URL=<redis cloud>`
- `CELERY_RESULT_BACKEND=<redis cloud>`

---

## 3) Déploiement cloud backend (Render recommandé)

Le projet inclut un blueprint:

- `render.yaml`

Il crée:

- 1 service Web Django (`gestion-school-api`)
- 1 worker Celery (`gestion-school-worker`)
- 1 scheduler Celery Beat (`gestion-school-beat`)
- 1 Redis (`gestion-school-redis`)

### Étapes

1. Pousser le repo sur GitHub.
2. Sur Render: **New + > Blueprint** et sélectionner le repo.
3. Dans les variables Render, renseigner au minimum:
	- `DATABASE_URL` (Supabase Session Pooler recommandé)
	- `SECRET_KEY` (forte)
	- domaines réels (`ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS`, `CSRF_TRUSTED_ORIGINS`).
4. Déployer.

> Si Render génère un domaine différent de `gestion-school-jkzf.onrender.com`, mets à jour ces 3 variables avec le domaine réel.

Le conteneur web exécute automatiquement migrations + collectstatic au démarrage.

---

## 4) Vérifications API publique

Tester:

`curl -I https://<api-publique>/api/auth/login/`

`405 Method Not Allowed` en GET est normal (endpoint actif).

Tester docs:

`https://<api-publique>/api/docs/`

---

## 5) Configurer les clients (mobile/web/desktop)

### Option A (rapide): via écran login

Dans l'écran login, ouvre **Configuration API** et saisis:

`https://<api-publique>/api`

### Option B (builds cloud figés)

Utiliser le script fourni:

`./build_cloud_clients.sh --api-url=https://<api-publique>/api`

Ou cibler seulement certaines plateformes:

`./build_cloud_clients.sh --api-url=https://<api-publique>/api --targets=apk,web`

Sorties:

- APK: `frontend/gestion_school_app/build/app/outputs/flutter-apk/app-release.apk`
- Web: `frontend/gestion_school_app/build/web/`
- Linux desktop: `frontend/gestion_school_app/build/linux/x64/release/bundle/`

---

## 6) Sauvegarde DB avec Supabase

La commande backup prend maintenant en charge MySQL **et** PostgreSQL:

`python manage.py backup_db`

Avec Supabase/PostgreSQL, elle utilise `pg_dump`.

---

## Résultat attendu

Une fois l'API Django déployée en cloud + base Supabase configurée:

- APK mobile fonctionne partout (4G/Wi-Fi)
- Web fonctionne sans ton PC allumé
- Desktop fonctionne depuis n'importe quel réseau avec URL API publique
- les tunnels locaux ne sont plus nécessaires en production
