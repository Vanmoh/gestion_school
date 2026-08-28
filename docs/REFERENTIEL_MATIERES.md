# Referentiel des matieres — arbitrages en attente

Le module « Academique » porte 193 matieres pour 34 noms distincts: chaque
matiere est rattachee a une classe, donc « Francais » existe 19 fois. Un
referentiel partage (`Subject` commun + `ClassroomSubject(classe, matiere,
coefficient)`) reglerait la duplication, mais la fusion ne peut pas etre
automatique — voir les deux obstacles ci-dessous.

Ce travail est **reporte**, pas abandonne. Les arbitrages deja rendus sont
consignes ici pour ne pas etre a refaire.

## Pourquoi la fusion ne peut pas etre automatique

**Les coefficients divergent pour un meme nom**, et c'est voulu: les maths
pesent 5 en serie scientifique et 1 en serie litteraire.

| Matiere | Classes | Coefficients |
|---|---|---|
| Francais | 19 | 1, 2 et 3 |
| Mathematiques | 16 | 1 et 5 |
| Physique-Chimie | 10 | 2 et 5 |
| TP | 7 | 1, 2 et 5 |

Une fusion qui retiendrait un seul coefficient fausserait toutes les
moyennes, donc les bulletins et les decisions de passage. C'est la table de
liaison qui doit porter le coefficient, par classe.

**Certaines matieres coexistent dans la meme classe.** Les rabattre l'une
sur l'autre creerait un doublon, ou melangerait deux enseignements.

## Arbitrages rendus

| Cas | Decision |
|---|---|
| `Histoire` + `Geographie` + `Histoire-Geographie` | **Une seule matiere** |
| `Dessin / Arts` + `Dessin technique` + `Dessin + TC` | **Variantes d'une seule** |
| `Langues`, `Chinois/Allemand` | A ranger sous **`Langue vivante 1`** et **`Langue vivante 2`** |
| `Sciences d'obsevation` | Faute de frappe: corriger en **`Sciences d'observation`** |
| `TP` et `LABO` | **Deux matieres distinctes** — elles coexistent en 1ere Annee EM1/EM2 avec des enseignants differents (Prof07 pour TP, Prof05 pour LABO) |

Variantes d'orthographe, sans ambiguite:

- `Education Civique et Morale (ECM)` -> `Éducation civique et morale (ECM)`
- `Education Physique et Sportive (EPS)` + `EPS` -> `Éducation physique et sportive (EPS)`
- `Mathematique (Math)` -> `Mathematiques`
- `Histoire-Geographie (Histoire-Geo)` -> `Histoire-Geographie`
- `PC` -> `Physique-Chimie` (a confirmer)
- `RDM` / `RMD` — l'un des deux est vraisemblablement une coquille (a confirmer)

## Piege connu, a traiter classe par classe

En **1ere Annee EM1**, `Langues`, `Langue vivante 1` et `Langue vivante 2`
coexistent toutes les trois: rabattre `Langues` sur LV1 y ferait un doublon.
En **1ere Annee EM2**, `Langues` est seule et devient LV1 sans conflit.

Deux classes, deux traitements: la reprise devra examiner chaque classe, pas
seulement chaque nom.

## Ce que la migration devra repointer

`Grade.subject`, `TeacherAssignment.subject`, `ExamPlanning.subject` et
`ExamResult.subject`. Une erreur y deplace des notes d'une matiere a l'autre,
sans bruit.
