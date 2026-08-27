# Concordance emploi du temps / émargement enseignants

L'emploi du temps dit ce qui **devait** être assuré, l'émargement ce qui **l'a
été**. Les deux vivaient côte à côte sans se regarder : une séance que
personne n'assurait ne remontait nulle part, et un pointage n'indiquait pas à
quel cours il correspondait.

## 1. Ce qu'un pointage retient désormais

Chaque `TeacherTimeEntry` enregistre les cours qu'il a réellement couverts,
un par ligne, dans `TeacherTimeEntryCoverage` : le créneau, les minutes
prévues, les minutes couvertes, le retard.

Auparavant, un seul créneau était deviné à la volée pour le calcul et jamais
conservé. C'est ce qui produisait le défaut le plus coûteux : **un enseignant
assurant 8h-10h puis 14h-16h et pointant de 8h à 16h était payé deux heures
au lieu de quatre**, le total étant plafonné à la durée d'un seul cours.

Les heures payables valent maintenant la **somme** des cours couverts,
chacun plafonné à sa propre durée. Ni l'avance avant le premier cours, ni la
pause de midi, ni le temps passé après le dernier cours ne sont payés : le
planning fait foi.

## 2. La tolérance de retard

Elle était figée à 15 minutes dans le code, la même pour toutes les écoles.
Elle se règle sur la fiche établissement — champ
`timesheet_late_tolerance_minutes` — et vaut 15 par défaut, ce qui laisse le
comportement inchangé pour qui n'y touche pas.

La tolérance ne s'applique qu'au **début** de chaque cours : arriver cinq
minutes en retard n'ampute pas l'heure, mais partir vingt minutes plus tôt
n'est pas la même chose qu'avoir assuré le cours.

## 3. Les pointages hors planning

Un pointage qui ne recoupe aucun cours — aucun créneau ce jour-là, ou tous
terminés avant l'arrivée — reste possible mais **exige un motif**
(`off_schedule_reason`) : remplacement, réunion, rattrapage.

Le refus sec d'avant fermait la porte à des présences parfaitement
légitimes, ce qui poussait à saisir de faux horaires un jour où l'enseignant
avait cours. Hors planning, c'est la durée de présence réelle qui est
retenue : il n'y a aucun cours auquel la comparer.

Le dimanche reste interdit, motif ou pas.

## 4. Le gel après validation de la paie

Corriger l'emploi du temps en décembre modifiait rétroactivement les heures
payables d'octobre — y compris sur un bulletin déjà validé par la
comptabilité et payé.

`TeacherTimeEntry.calcul_fige()` bloque désormais tout recalcul dès qu'une
`TeacherPayroll` du mois porte une validation de niveau deux. Les colonnes
libres (note, motif) restent modifiables ; les heures, non.

Pour reprendre le calcul d'un mois figé, il faut passer par la régénération
forcée de la paie, qui lève les validations (`force_regenerate`).

## 5. L'API de rapprochement

```
GET /api/teacher-time-entries/concordance/?from=AAAA-MM-JJ&to=AAAA-MM-JJ[&teacher=<id>]
```

Retourne, par enseignant et par jour, chaque séance planifiée avec son
statut :

| Statut | Signification |
| --- | --- |
| `assured` | Couverte d'un bout à l'autre (tolérance incluse) |
| `partial` | Couverte en partie : retard au-delà de la tolérance, ou départ anticipé |
| `missed` | Aucun pointage ne la recoupe — personne ne l'a assurée |

Plus les pointages du jour, ceux hors planning étant marqués, et les totaux :
heures planifiées, heures assurées, écart, nombre de séances par statut.

**Bornes.** La période est limitée à 62 jours : au-delà, la réponse porte des
milliers de séances et l'écran n'en fait rien. Un enseignant ne voit que sa
propre concordance ; les autres profils voient leur établissement.

**Les enseignants sans aucun pointage y figurent aussi** — c'est précisément
celui qui a été absent toute la semaine que l'on cherche, et il n'a aucune
ligne de pointage à son nom.

## 6. Le signalement quotidien

```
manage.py signaler_seances_non_assurees              # la veille
manage.py signaler_seances_non_assurees --jour 2026-03-12
manage.py signaler_seances_non_assurees --dry-run
```

Planifiée à 6h30 (`CELERY_BEAT_SCHEDULE`, tâche
`apps.school.tasks.signaler_les_seances_non_assurees`), la commande notifie
le super-administrateur, la direction et le censeur de chaque établissement
concerné.

**La veille et non le jour même** : un cours de l'après-midi n'est pas encore
manqué à midi. **Un seul message récapitulatif par responsable** : cinq cours
manqués un jour de grève ne doivent pas produire cinq alertes identiques
dans la même boîte.

## 7. Ce que la fiche de paie en dit

`hours_attributed` moins `hours_worked` se lisait sans qu'on sache d'où venait
la différence. La fiche porte désormais deux colonnes qui la décomposent :

- `hours_missed` — des séances planifiées que personne n'a assurées ;
- `hours_off_schedule` — des heures faites en dehors du planning.

Les deux se pilotent autrement : l'une appelle un remplaçant, l'autre une
régularisation. Elles sont vides sur les fiches émises avant cette mise à
jour, qui ont été payées sur ce qu'elles portaient.

## 8. Les écrans

- **Émargement > Enseignants** : le rapprochement du jour affiché, séance par
  séance avec sa pastille, et le champ « motif hors planning » qui se signale
  de lui-même quand le serveur va l'exiger. Le tableau des pointages porte
  une colonne « Séances » qui nomme les cours couverts.
- **Bouton « Sur une période »** : le même rapprochement sur une plage libre,
  le mois courant par défaut — c'est la maille de la paie, donc celle sur
  laquelle l'écart se discute.
- **Emploi du temps** : les créneaux non assurés de la semaine en cours
  ressortent en rouge sur la grille. Le recul sur d'autres périodes se prend
  depuis l'émargement, dont le rapprochement porte les dates.
