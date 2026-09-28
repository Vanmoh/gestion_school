# Qui enseigne quoi : les règles, et où elles tiennent

Trois règles de métier, posées en septembre 2026 après qu'un emploi du temps
« complet » a laissé trente et un enseignants sans une heure de cours. Elles
tiennent ensemble, et chacune ferme une porte que la précédente laissait ouverte.

## 1. Une matière, un enseignant

> Un enseignant tient plusieurs matières ; une matière n'a qu'un titulaire à la
> fois.

La seconde moitié de cette phrase n'était écrite qu'à **un seul endroit** : le
`validate()` de `TeacherAssignmentSerializer`. Elle était donc vraie pour qui
passe par l'API, et fausse pour tout le reste. Le modèle la contredisait :

```python
unique_together = ("teacher", "subject", "classroom")
```

Cela interdit d'affecter **deux fois le même** enseignant à une matière, et
laisse passer **deux enseignants différents**.

### Ce que ça cassait, et pourquoi on ne le voyait pas

Une matière à deux titulaires réclame deux fois son volume horaire. Une classe a
`len(JOURS) × len(CRENEAUX)` places par semaine — **36**. Avec huit matières à
deux titulaires, une classe de quatorze matières posait 36 créneaux pour un
volume de 30 : la grille débordait, la marge nécessaire au placement disparaissait,
et les derniers servis n'obtenaient rien.

**Un bulletin ne dit pas qui enseigne.** Aucun écran ne rapprochait « emploi du
temps complet » de « cet enseignant n'a aucune heure ». Le défaut a vécu
longtemps.

### Où elle tient maintenant

| niveau | mécanisme |
|---|---|
| base de données | `UniqueConstraint(fields=["subject", "classroom"], name="une_matiere_un_enseignant")` |
| migration | `0071_une_matiere_un_enseignant` — tranche d'abord, contraint ensuite |
| API | `TeacherAssignmentSerializer.validate()`, message français nommant le titulaire |
| reprise d'année | `views.py` reprend le titulaire en place au lieu d'en ajouter un second |
| dotation | `_une_matiere_un_enseignant()` retire les concurrents de son périmètre |
| `assign_subjects_to_classes` | vérifiait déjà |

La migration se fait en deux temps, et l'ordre est contraint : **on ne peut pas
poser une contrainte sur une base qui la viole.** Elle garde donc l'affectation
de celui qui enseigne réellement — le plus d'heures posées — et à égalité la plus
ancienne, qui est le choix qu'avait fait l'école. Le retour en arrière retire la
contrainte et ne rend pas les affectations supprimées : il ne peut pas, leur
trace n'existe plus.

### Un piège à connaître

DRF 3.15 déduit un validateur de `Meta.constraints` et répond :

> The fields subject, classroom must make a unique set.

En anglais, sans dire à qui la matière est confiée, et **avant** `validate()`.
D'où `Meta.validators = []` sur le serializer, qui désactive ceux que DRF déduit
du modèle. Rien n'est perdu : `validate()` couvre (matière, classe), donc à plus
forte raison (enseignant, matière, classe). Un test vérifie que « unique set »
n'apparaît jamais dans la réponse.

## 2. On ne pointe que quelqu'un qui enseigne

> Un pointage dit si l'enseignant a assuré ses cours. La question ne se pose pas
> pour quelqu'un qui n'enseigne rien.

`TeacherAttendance` et `TeacherTimeEntry` portent un `teacher` **en direct**,
sans lien vers l'affectation. Rien ne s'y opposait, et la base de développement
comptait **920 pointages et 554 émargements** pour 52 enseignants sans une
matière — un registre d'absences ne dit pas qui enseigne quoi, donc personne ne
pouvait le voir.

La règle vit dans [enseignement.py](../backend/apps/school/enseignement.py) et
tient à deux endroits :

- un **`pre_save`** sur les deux modèles — parce que le serializer ne couvre que
  l'API, et que c'est par une **commande** que ces lignes sont arrivées. Le signal
  est le seul point de passage commun à l'API, aux commandes, à l'admin Django et
  au code qu'on écrira demain ;
- le **`validate()`** du serializer, pour que l'écran réponde une phrase utile
  plutôt qu'une erreur d'intégrité.

Le message nomme l'enseignant et dit quoi faire :

> Ce pointage est impossible : aucune matière n'est affectée à Fatoumata TRAORE.
> Affectez-lui d'abord une matière dans « Enseignants > Affectations ».

## 3. Le créneau n'a besoin d'aucune garde

`TeacherScheduleSlot` ne porte **pas** de champ `teacher` : il pend à
`assignment`.

```
TeacherScheduleSlot.assignment → TeacherAssignment (teacher, subject, classroom)
```

Un créneau sans affectation ne peut donc pas exister, et une affectation nomme
exactement une matière et une classe. La règle y tient **par construction**, ce
qui vaut mieux qu'une vérification : aucun signal à oublier, aucun chemin à
couvrir. Deux tests le fixent, pour qu'un refactor qui ajouterait un `teacher`
sur le créneau soit signalé.

## Ce que les règles n'exigent pas, et pourquoi

Une règle trop large casse un usage légitime, et finit désactivée. Trois
exemptions, chacune délibérée :

- **les disponibilités** ne demandent aucune affectation. La direction les
  collecte **pour** arbitrer les affectations : exiger une matière inverserait
  l'ordre des choses, et un enseignant qui arrive ne pourrait pas déclarer les
  siennes ;
- **une fiche de paie d'un mois passé** reste due à qui n'enseigne plus
  aujourd'hui. On cesse d'en **créer** de nouvelles à zéro franc — la génération
  mensuelle ignore les non-affectés — mais on n'interdit pas leur existence ;
- **surveiller une épreuve** ne demande pas d'enseigner la matière.

## Nettoyer une base existante

```bash
# Dire si la base respecte les règles (le remède voyage avec chaque anomalie).
python manage.py controler_la_dotation

# Retirer ceux qui ne tiennent plus rien. Simulation par défaut.
python manage.py retirer_les_enseignants_sans_matiere
python manage.py retirer_les_enseignants_sans_matiere --desactiver --appliquer
```

`retirer_les_enseignants_sans_matiere` épargne par défaut les comptes que l'école
a saisis — la base de développement contenait le compte personnel de son
propriétaire parmi les sans-matière — et refuse ceux qui portent une fiche de
paie. `--desactiver` est préférable à la suppression : l'accès part, l'historique
reste, et c'est réversible.

Son inventaire compte `collector.fast_deletes` **en plus** de `collector.data`.
Django range dans le premier les suppressions qu'il fait en une requête, sans
charger les objets : une première version annonçait 44 suppressions pour près de
2 000 réelles. Un rapport qui annonce moins que ce qu'il fait est pire qu'absent.
