# Architecture technique - GESTION SCHOOL

## Backend (Django + DRF)
- `apps/accounts` : utilisateurs, rôles, JWT, profil
- `apps/school` : modules métier (élèves, académique, notes + validation direction, absences élèves/enseignants, discipline, finance, communication, bibliothèque, cantine, examens + attribution surveillants, stock)
- `apps/reports` : génération PDF/Excel
- `apps/common` : utilitaires partagés, backups, journal d'activités (audit + filtres/tri + export Excel/PDF)

### Clean separation
- `presentation`: API DRF (views, urls)
- `domain`: règles métier (modèles + fonctions de calcul)
- `data`: persistance ORM MySQL

## Frontend Flutter
- `core/`: constantes, réseau, thèmes, erreurs
- `features/auth`: connexion JWT
- `features/dashboard`: statistiques et graphiques
- `features/students`: listing élèves
- `features/reports`: génération PDF côté client (exemple)

## Sécurité
- JWT Bearer obligatoire sur endpoints protégés
- Permissions de base par rôle (`IsAdminOrDirector` + `IsAuthenticated`)
- CORS configurable par variables d’environnement

## Scalabilité
- API stateless
- Worker Celery séparé
- Redis pour queue/task
- Structure prête pour découpage en microservices si nécessaire
