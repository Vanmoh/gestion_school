# Procédure de rentrée

De l'établissement vide à la première journée de classe. À suivre dans
l'ordre: chaque étape s'appuie sur la précédente.

Comptez une demi-journée pour une école de cinq cents élèves, l'essentiel du
temps étant la préparation des fichiers d'import.

---

## 0) Avant de commencer — vérifications

```bash
cd backend
python manage.py check --deploy
```

Ce contrôle doit être **silencieux**. S'il parle, traitez-le avant d'ouvrir
l'année:

| Code | Ce qu'il dit | Où le régler |
|---|---|---|
| `W001` | Les fichiers téléversés vivent sur un disque éphémère | `AWS_STORAGE_BUCKET_NAME` |
| `W003` | Région du stockage objet absente: les photos répondront 403 | `AWS_S3_REGION_NAME` |
| `W004` | La couche temps réel pointe sur l'hôte de développement | `CHANNEL_REDIS_URL` |
| `W005` | **Des comptes de démonstration existent en production** | `manage.py purger_comptes_demo` |
| `W006` | Aucune notification ne partira | [NOTIFICATIONS_PUSH.md](NOTIFICATIONS_PUSH.md) |

Purger les comptes de démonstration est **impératif**: leur mot de passe est
public, et `superadmin` est super-utilisateur.

```bash
python manage.py purger_comptes_demo --dry-run   # liste sans rien changer
python manage.py purger_comptes_demo
python manage.py createsuperuser                 # votre vrai compte
```

---

## 1) Créer l'établissement

Écran **Établissements**. Renseignez au minimum:

- **Nom** et **code** — le code préfixe les matricules des élèves, il ne se
  change plus une fois des élèves inscrits;
- logo, cachet, signature du principal: ils apparaissent sur les bulletins,
  les reçus et les cartes scolaires;
- **Coefficient de conduite** (2 par défaut) — il pèse dans la moyenne du
  bulletin *et* dans le classement. À 0, la conduite est notée sans peser.

## 2) Ouvrir l'année scolaire

Écran **Vie scolaire → Années scolaires**. Dates de début et de fin: elles
bornent tout le reste — échéances de frais, absences, bulletins. Une échéance
hors de ces dates est refusée.

## 3) Créer les classes et les matières

Écran **Vie scolaire**. Les matières sont rattachées à une classe et portent
leur **coefficient**: c'est lui qui pondère les moyennes.

## 4) Importer les élèves

Écran **Imports académiques** → *Modèle de fichier*, puis remplir et
renvoyer. Colonnes attendues: `matricule`, `first_name`, `last_name`,
`genre`, `birth_date`.

Le **genre est obligatoire**: le matricule l'encode dans sa dernière lettre.

L'import refuse le fichier entier dès qu'une ligne est fausse — un import à
moitié passé laisse une base dont personne ne sait où elle en est.

## 5) Poser les barèmes de frais

Écran **Finances → Barèmes**. C'est l'étape qui remplace cinq mille saisies à
la main.

Pour chaque classe, créer une ligne par type de frais:

| Type | Montant | Première échéance | Échéances |
|---|---|---|---|
| Frais d'inscription | 25 000 | 15/10/2025 | 1 |
| Frais mensuels | 10 000 | 05/11/2025 | 9 |

Puis, dans l'ordre:

1. **Aperçu** sur chaque barème — il annonce le nombre d'élèves, les dates
   produites et le **total à facturer**. Une erreur de montant se multiplie
   par le nombre d'échéances et par la classe entière: relisez ici.
2. **Tout appliquer** — les frais de tous les élèves sont créés d'un coup.

Réappliquer un barème ne crée que les frais manquants: c'est ainsi qu'on
rattrape un élève inscrit en janvier, sans redonner à sa classe une seconde
série de mensualités. **Refaites-le après chaque vague d'inscriptions.**

Pour les cas particuliers — tarif négocié, bourse partielle, échéancier
propre à un élève — utilisez **Importer des frais** (colonnes
`student_matricule`, `fee_type`, `amount_due`, `due_date`).

## 6) Créer les comptes du personnel

Écran **Utilisateurs**. Chaque compte reçoit un rôle, et le rôle décide de
tout: la matrice des droits est la seule source (`apps/accounts/access.py`).

Un compte ne peut agir que sur les comptes de rang inférieur au sien.

## 7) Créer les comptes des familles

Les parents ont besoin d'un compte pour consulter notes, absences et frais.
Rattachez chaque élève à sa fiche parent (écran **Élèves**, section
*Contacts*): c'est ce lien qui donne au parent l'accès au dossier de son
enfant, et à lui seul.

Le mot de passe provisoire se pose depuis l'écran Utilisateurs
(*Réinitialiser le mot de passe*). Il n'expire pas: demandez aux familles de
le changer.

## 8) Emplois du temps

Écran **Emploi du temps**. La saisie détecte les conflits — même classe, même
enseignant, même salle au même moment — et refuse le créneau en nommant celui
qui gêne.

Un import Excel existe aussi (**Imports académiques**).

## 9) Vérifier avant d'ouvrir

- [ ] `manage.py check --deploy` silencieux
- [ ] Aucun compte de démonstration (`purger_comptes_demo --dry-run`)
- [ ] Un élève test voit ses frais, et rien de plus
- [ ] Un parent test voit son enfant, et pas les autres
- [ ] Un bulletin sort en PDF avec logo, cachet et signature
- [ ] Un reçu de paiement sort en PDF
- [ ] La sauvegarde tourne (`manage.py backup_db`)

---

## Pendant l'année

**À chaque vague d'inscriptions** — réappliquer les barèmes (§5).

**À chaque fin de trimestre**, dans cet ordre:

1. Saisir les notes de classe et les compositions;
2. **Clôturer le trimestre** (écran Notes → *Valider la période*): le
   classement est calculé et figé à ce moment, par trimestre;
3. **Publier les résultats d'examen** (écran Examens) — tant que ce n'est pas
   fait, les familles ne voient pas les notes de composition;
4. **Valider les bulletins** de la classe, puis les envoyer aux familles.

Un bulletin réimprimé plus tard porte toujours le rang de son trimestre.

**En fin d'année** — écran **Promotion**: simuler d'abord, relire les
décisions, puis exécuter. La moyenne annuelle est la moyenne des trimestres
évalués, conduite comprise: **relisez le seuil de passage**, car la conduite
(18 par défaut) remonte les moyennes.

## Reprise d'un historique existant

Pour une année clôturée avant l'ajout du classement par trimestre, les
bulletins anciens affichent « - » à la place du rang. Reconstruisez-les à
partir des notes, qui sont toujours en base:

```bash
cd backend
python manage.py recalculer_rangs --etab-id=<id> --dry-run
python manage.py recalculer_rangs --etab-id=<id>
```
