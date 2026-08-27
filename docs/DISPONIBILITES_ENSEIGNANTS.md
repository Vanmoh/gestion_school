# Disponibilités des enseignants

Ce que les enseignants déclarent **avant** que l'emploi du temps existe, et
comment cette collecte sert ensuite à le construire.

## 1. Le bug qui rendait le module inutilisable

L'unicité portait sur `(etablissement, day_of_week, start_time, end_time)` —
**sans l'enseignant**. Le premier à déclarer « lundi 08:00-10:00 » en devenait
propriétaire exclusif pour toute son école, et le suivant se heurtait à une
erreur d'intégrité en base :

```
IntegrityError: UNIQUE constraint failed:
  etablissement_id, day_of_week, start_time, end_time
```

Dans un établissement de vingt enseignants, le module cessait d'être
utilisable dès le deuxième répondant. Le sérialiseur allait dans le même
sens (« Ce créneau est déjà réservé et n'est plus disponible. Réservé par :
X »), et l'écran l'affichait noir sur blanc.

L'unicité porte désormais sur `(teacher, day_of_week, start_time, end_time)`.
Dix enseignants peuvent déclarer le même lundi matin — c'est précisément ce
que l'administration a besoin de savoir pour arbitrer. La détection de
chevauchement se borne au **même déclarant** : on l'empêche de se déclarer
deux fois sur la même plage, on ne le prive plus de celle d'un collègue.

## 2. Les trois états

| État | Sens |
| --- | --- |
| `preferred` — Préférée | « Je veux bien ce créneau » |
| `possible` — Possible | « Je peux, sans plus » |
| `unavailable` — Indisponible | « Je ne peux pas », avec sa raison dans `note` |

Trois et non deux : une collecte sert justement à recueillir la nuance. Le
troisième état permet aussi de dire franchement non — un cours dans un autre
établissement, une obligation le mercredi après-midi — là où le modèle ne
connaissait que des créneaux positifs.

**L'absence de déclaration reste une information à part entière** : elle ne
vaut ni oui ni non, et la voir comptée à part est ce qui permet de relancer
les bonnes personnes.

## 3. La campagne de collecte

`AvailabilityCampaign` borne la collecte : un établissement, une année
scolaire, une date d'ouverture et une de fermeture, un statut.

```
GET/POST  /api/availability-campaigns/
GET       /api/availability-campaigns/<id>/responses/   # qui a répondu, qui manque
POST      /api/availability-campaigns/<id>/remind/      # relance les manquants
POST      /api/availability-campaigns/<id>/submit/      # « j'ai terminé » (enseignant)
```

Une seule campagne par établissement et par année : deux collectes ouvertes
en parallèle rendraient indécidable celle à laquelle rattacher une
déclaration. Les créneaux déclarés se rattachent automatiquement à la
campagne ouverte, donc à son année scolaire — celles de l'an dernier cessent
de se mêler à celles de la rentrée.

**Qui peut déclarer quand.** L'enseignant ne saisit que pendant la collecte
ouverte ; l'administration garde la main en permanence, y compris après la
clôture — c'est son travail d'arbitre, et l'en priver la renverrait vers la
base de données. Une école qui n'a **aucune** campagne continue à déclarer
comme avant : la nouveauté ne bloque pas qui ne l'a pas encore adoptée.

`submit` est ce qui sépare le silence de l'indisponibilité. Sans lui, une
grille vide pouvait aussi bien vouloir dire « je ne peux jamais » que « je
n'ai pas encore ouvert l'écran ».

## 4. Ce qui sert à construire le planning

```
GET /api/teacher-availability-slots/for-planning/?day=MON&start=08:00&end=10:00
```

Rend les enseignants en quatre groupes, dans l'ordre où l'administration les
regarde : `preferred`, `possible`, `undeclared`, `unavailable`.

**Une déclaration ne compte que si elle contient entièrement le créneau
visé.** Une heure déclarée ne couvre pas un cours de deux heures : l'enseignant
n'a jamais dit pouvoir la seconde heure.

## 5. Le placement hors disponibilité

Placer un cours en dehors de ce que l'enseignant a déclaré reste possible —
l'administration arbitre entre des contraintes que l'enseignant ne connaît
pas — mais exige un motif, conservé dans
`TeacherScheduleSlot.off_availability_reason`.

**Le motif n'est exigé que si l'enseignant a déclaré quelque chose ce
jour-là.** Ne rien exiger de celui qui s'est tu évite de bloquer l'emploi du
temps entier d'une école qui n'a pas encore lancé sa collecte.

Le message nomme la cause : soit l'indisponibilité déclarée avec sa note,
soit les plages effectivement déclarées ce jour-là.

## 6. La grille

```
GET /api/teacher-availability-slots/grid/?start_hour=7&end_hour=18&slot_minutes=60[&teacher=<id>]
```

Elle rendait auparavant « disponible » ou « indisponible » pour
l'établissement entier et nommait celui qui avait « réservé » la case. Elle
rend désormais deux lectures à la fois, parce que deux écrans la consultent :

- `preferred_count` / `possible_count` / `unavailable_count` et la liste des
  déclarants — ce dont l'administration a besoin pour arbitrer ;
- `mine` / `mine_id` / `mine_exact` — ce que l'enseignant visé a déclaré sur
  cette case.

`mine_exact` vaut faux quand une plage plus large couvre la case sans lui
correspondre : la modifier depuis là découperait la déclaration d'origine,
ce que l'écran refuse de décider à la place du déclarant.

Les compteurs restent ceux de l'établissement même quand on filtre par
enseignant. L'ancienne grille affichait « Disponible » sur les cases prises
par d'autres dès qu'on filtrait, et l'échec n'arrivait qu'au moment
d'enregistrer.

## 7. Les écrans

**Enseignant** — une grille hebdomadaire qu'il peint en touchant les cases :
préférée → possible → indisponible → rien. Le bandeau porte l'échéance et le
bouton « J'ai terminé ». Les déclarations de ses collègues ne lui sont pas
montrées : elles l'influenceraient sans le renseigner.

**Administration** — la même grille en vue d'ensemble, où chaque case porte
le **nombre** d'enseignants prenables, avec une intensité de couleur qui suit
ce nombre : une case pâle est une case où l'on n'aura pas le choix, une case
cerclée de rouge une case où personne n'est disponible. Le bandeau porte le
taux de réponse, la relance et le suivi. Le sélecteur permet aussi de saisir
à la place d'un enseignant.

## 8. Droits

Matrice `teacher_availability` (`apps/accounts/access.py`) : administration en
écriture complète, censeur en écriture, enseignant en écriture sur **ses
propres** créneaux. La relance des collègues est refusée à l'enseignant même
si la matrice lui ouvre l'écriture — elle ouvre la déclaration, pas la
gestion de la campagne.
