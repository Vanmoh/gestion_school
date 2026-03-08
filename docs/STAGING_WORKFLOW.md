# Flux staging (test en ligne sans impacter la prod)

Ce flux permet de tester en conditions réelles (4G/5G, URL publique) avant d'envoyer en production.

## 1) Branches Git

Première mise en place:

```bash
git checkout main
git pull origin main
git checkout -b staging
git push -u origin staging
```

Cycle standard:

- tu développes localement puis commits sur `staging`
- Render staging auto-déploie depuis la branche `staging`
- quand tout est validé, tu merges `staging` -> `main`
- la prod déploie depuis `main`

Push one-click vers staging:

```bash
./push_to_staging.sh
```

Simulation sans push:

```bash
./push_to_staging.sh --dry-run
```

## 2) Service Render staging

Le fichier blueprint staging est:

- `render.staging.yaml`

Étapes Render:

1. Dashboard Render -> **New +** -> **Blueprint**
2. Sélectionne le repo GitHub
3. Blueprint file path: `render.staging.yaml`
4. Crée le service

Le service créé est `gestion-school-staging-api` et suit la branche `staging`.

## 3) Variables à renseigner dans staging

Obligatoire:

- `DATABASE_URL` (idéalement une base Supabase dédiée staging)

Déjà présent dans le blueprint:

- `DEBUG=False`
- `CORS_ALLOW_ALL_ORIGINS=True` (simple pour tests)
- cookies sécurisés + trusted origins Render

## 4) Validation staging

Endpoints utiles:

- `https://gestion-school-staging-api.onrender.com/api/docs/`
- `https://gestion-school-staging-api.onrender.com/api/auth/login/`

Depuis l'app Flutter, utilise l'URL API staging:

- `https://gestion-school-staging-api.onrender.com/api`

## 5) Promotion vers prod

Quand staging est validé:

```bash
git checkout main
git pull origin main
git merge --no-ff staging
git push origin main
```

Ensuite Render prod déploie automatiquement depuis `main`.

Alternative one-click:

```bash
./promote_staging_to_main.sh
```
