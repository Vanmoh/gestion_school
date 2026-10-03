# Une liste a un ordre, et « le premier » doit vouloir dire quelque chose

Le 28 septembre 2026, « Notes & Bulletins » a affiché **« Aucune note
enregistrée »** sur une base qui en comptait 68 397. Les bulletins imprimés
portaient des tirets partout — seule la conduite s'y voyait, parce qu'elle vaut
18 par défaut et ne dépend d'aucune saisie.

Rien n'était cassé. L'en-tête disait « 2025-2026 · Active », le sélecteur de
l'écran disait « 2026-2027 » : on interrogeait simplement une autre année.

Ce document existe parce que la cause n'était pas là où le symptôme s'affichait,
et que le même piège attend n'importe quel écran.

## La cause, en deux moitiés

### Aucun ordre n'était défini

`AcademicYear` n'avait d'ordre ni sur son modèle, ni sur sa vue. Une requête
sans `ORDER BY` rend les lignes dans l'ordre physique de la table — et
**PostgreSQL déplace une ligne en fin de table quand on la met à jour**.

« La première année » a donc changé de sens un jour, sans qu'une seule ligne de
code ne bouge. C'est ce qui rendait le défaut si déroutant : il n'y avait rien à
trouver dans l'historique.

### Six écrans prenaient « la première »

Notes, bulletins, cantine, historique de l'élève, frais de l'élève, campagnes
d'examens : tous retenaient `annees.first` sans regarder `is_active`.

La règle existait pourtant déjà dans le projet — `AnneeScolaireController`
l'applique pour le sélecteur global : **l'année active de l'établissement, à
défaut la plus récente**. Elle n'était simplement pas accessible aux écrans qui
manipulent des `Map` brutes.

## Ce qui est en place maintenant

| | |
|---|---|
| [`annee_a_retenir.dart`](../frontend/gestion_school_app/lib/core/academics/annee_a_retenir.dart) | la règle, pour les écrans qui lisent des `Map` de l'API |
| `OptionItem.estCourante` | le drapeau, pour les écrans qui lisent des objets typés |
| `AcademicYearViewSet.ordering` | `-is_active, -start_date, -id` : l'année active arrive première |
| [`test_les_listes_ont_un_ordre_total.py`](../backend/apps/school/tests/test_les_listes_ont_un_ordre_total.py) | le garde-fou, décrit plus bas |

`promotion_page` est laissé tel quel : sa source est déjà choisie sur
`is_active`, et sa « première » sert à proposer une année **cible**, ce qui est
voulu.

## Le vrai enjeu : la pagination

En cherchant tous les endroits ayant le même défaut, un problème plus large est
apparu — et il ne se voit jamais à l'écran.

La pagination est globale : `StandardResultsSetPagination`, cent lignes par
page. **Une liste paginée dont l'ordre laisse des ex aequo n'est pas stable
d'une page à l'autre.** La base est libre de départager comme elle veut, et elle
ne le fait pas deux fois pareil : une ligne peut apparaître deux fois, ou
disparaître entre la page 1 et la page 2. Sans erreur, sans rien dans les
journaux.

Ce n'est pas théorique ici : `doter_les_etablissements_reels` crée des milliers
de lignes dans la même transaction, et un tri sur `-created_at` seul les laisse
**toutes** à égalité.

Le recensement a trouvé **15 listes sur 46** dans ce cas — dont
`AcademicYearViewSet`, que je venais moi-même de corriger à moitié. Toutes ont
reçu un départage final sur `id`.

Trois d'entre elles tenaient leur ordre du `Meta.ordering` de leur modèle. Le
départage a été posé **sur la vue**, pas sur le modèle : l'ordre d'un modèle
entre dans toutes ses requêtes, y compris les `distinct()`, où il rend chaque
ligne unique et fait échouer le dédoublonnage — un piège que ce dépôt a déjà
rencontré sur le journal d'activité.

## La règle, et comment elle se défend toute seule

> Toute liste servie par l'API a un ordre, et cet ordre se termine par une
> colonne unique.

`test_les_listes_ont_un_ordre_total.py` parcourt **toutes** les vues de liste du
projet et échoue en les nommant. Il protège donc celle qu'on ajoutera demain
sans y penser : corriger les quinze d'aujourd'hui ne protège que d'aujourd'hui.

Il porte aussi un troisième test, moins évident et non moins utile : il vérifie
que l'introspection trouve encore des vues. Sans lui, un module renommé ferait
passer les deux autres en ne vérifiant plus rien.

Une vue qui aurait une raison de ne pas suivre la règle s'inscrit dans
`EXEMPTEES` avec son motif. Le dictionnaire est vide aujourd'hui : il existe
pour qu'on motive une exception plutôt que de désactiver le test.

## Ce qu'on retiendra pour la prochaine fois

**Un écran vide n'accuse pas la base.** Le premier réflexe a été de croire les
données perdues ; elles étaient toutes là. Avant de chercher un coupable,
vérifier ce que l'écran demande — et le comparer à ce que l'en-tête affiche.

**`.first` sur une liste métier est une question, pas une réponse.** S'il existe
un critère juste — actif, en cours, par défaut — il faut le nommer. Sinon,
s'assurer au moins que l'ordre est défini, faute de quoi « le premier » change
tout seul.
