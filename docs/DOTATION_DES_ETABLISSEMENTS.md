# Doter les quatre établissements réels

`doter_les_etablissements_reels` monte une école entière et, sans argument, les
quatre : LTOB, LOBK, IFP-OBK et CSOB.

Avant elle, le dépôt savait créer des classes (`insert_classes`), des matières
pour deux écoles (`assign_subjects_to_classes`), des élèves pour une seule
(`seed_ltob_data`) et des notes à la demande (`seed_term_scores`). Aucune
commande ne montait une école de bout en bout, et aucune ne montait les quatre.

Deux scripts à la racine du dépôt l'enchaînent en un appel :

```bash
./peupler_les_quatre_ecoles.sh          # démarre Postgres, migre, dote, vérifie
./remettre_la_base_a_neuf.sh            # base vide, migrée, sans données de démo
./remettre_la_base_a_neuf.sh --puis-peupler
```

Le premier **échoue si la base n'est pas utilisable** : il appelle
`controler_la_dotation`, qui donne un verdict et non un journal. Un peuplement
qui se termine sans erreur n'est pas un peuplement utilisable.

```bash
# Les quatre écoles, trente élèves par classe, les trois trimestres notés.
python manage.py doter_les_etablissements_reels

# Une seule école, pour une vérification rapide.
python manage.py doter_les_etablissements_reels \
    --etablissement "Lycée Oumar Bah (LOBK)" --eleves-par-classe 5 --sans-notes
```

## Ce qu'elle monte, dans l'ordre où une école se monte

1. **l'année scolaire**, si elle manque ;
2. **les classes**, lues dans `insert_classes` — jamais devinées ;
3. **les matières** de chaque classe, déduites de sa filière : « 11ème CG » est
   de la gestion, « 2ème Année EM1 » de l'électromécanique. Le volume horaire
   suit le coefficient, sans quoi la génération d'emploi du temps n'a rien à
   placer ;
4. **les élèves**, noms et prénoms maliens, trente par classe par défaut ;
5. **les enseignants** et leurs affectations : un enseignant tient une matière,
   et la tient dans toutes les classes où elle s'enseigne ;
6. **l'emploi du temps**, puis sa publication. Aucun enseignant n'en sort sans
   heures : il enseigne, donc il en a ;
7. **le calendrier des compositions** : trois campagnes, une épreuve par matière
   et par classe. Il est dressé même avec `--sans-notes` — une école arrête ses
   dates avant d'avoir corrigé quoi que ce soit ;
8. **les notes** des trois trimestres, entre 9 et 19 : trois devoirs et une
   composition ;
9. **l'encadrement** : directeur, censeur, comptable, surveillant, promoteur ;
10. **les familles**, un parent par fratrie ;
11. **les frais** : un barème par classe, l'inscription réglée par tous, la
    scolarité soldée par trois élèves sur quatre ;
12. **le quotidien** : appel, pointage, discipline, bulletins arrêtés,
    surveillance des épreuves, disponibilités, paie, dépenses, bibliothèque,
    cantine, stock, annonces et messagerie ;
13. **les bilans trimestriels** — c'est ce qui fait qu'un bulletin du premier
    trimestre réimprimé en juin porte toujours le rang de décembre ;
14. **l'émargement** : l'heure d'arrivée et de départ, quinze jours durant.
    `TeacherAttendance` dit si une séance a été assurée, `TeacherTimeEntry` à
    quelle heure l'enseignant est arrivé : deux écrans distincts ;
15. **la remise des bulletins** aux familles, dans les quatre états — préparé,
    envoyé, consulté, échoué ;
16. **les abonnements à la cantine**, dont un suspendu et un terminé ;
17. **le fonds numérique** : collections, catégories et documents, dont un en
    erreur d'import ;
18. **le conseil de fin d'année**, **simulé et non exécuté**.

### Trois points qui méritent d'être dits

**La conduite suit les incidents.** Un incident consigné laissait la note à 18 :
le bulletin l'ignorait, et le conseil de fin d'année promouvait toute l'école
sans un redoublant. Le retrait est de 1, 3 ou 9 points sur 20 selon la gravité.
C'est `update_or_create` et non un décrément : relancée, la commande ne creuse
pas la note un peu plus à chaque passage.

**Le conseil de fin d'année est une simulation.** L'exécuter déplacerait les
1 260 élèves dans les classes de l'année suivante et déferait tout ce qui
précède. La simulation montre le même écran — effectifs, promus, redoublants —
et ne touche à rien. La classe cible se déduit du nom quand elle existe
(« 10ème CT » vers « 11ème CT ») et reste vide sinon : mieux vaut une cible
absente qu'une cible fausse.

**Les familles portent un numéro.** Elles n'en avaient aucun, et cela vidait
tout un pan de l'application : `ParentProfile.whatsapp_phone` se remplit depuis
`User.phone` par signal, et sans numéro la remise d'un bulletin par WhatsApp
n'avait nulle part où aller. Les élèves n'en ont pas : c'est la famille qu'on
joint.

## Les proportions ne sont pas approximatives

| Consigne | Ce que la commande tient |
|---|---|
| Frais d'inscription | réglés par **tous** les élèves |
| Scolarité | **exactement** un quart non soldé (`--part-non-soldee`), la part demandée étant un plafond |
| Notes | aléatoires entre **9 et 19** |
| Enseignants sans heures | **aucun** |
| Épreuves sans surveillant | **une sur sept**, pour que l'onglet ait de quoi dire |
| Articles sous leur seuil | **un seul**, pour que l'alerte soit lisible |
| Remises de bulletin | **toutes** les familles, dans les **quatre** états |
| Redoublants | ceux dont la **conduite** passe sous 10 |
| Émargement et paie | **tous** les enseignants affectés, recrutés ici ou déjà présents |
| Abonnés à la cantine | **40 %** de l'effectif, et non un nombre fixe |
| Volume horaire d'une classe | **jamais plus de 36 heures**, la capacité de la grille |

Les proportions sont des **parts**, jamais des plafonds absolus. « Quarante-cinq
abonnés » donnait 11 % dans une école de 450 élèves et 35 % dans une de 150 : la
même base racontait deux écoles différentes.

Le quart exact vient d'un tirage global, pas d'un tirage par élève : par élève,
la proportion dérivait à 28 %.

Le décompte est `effectif * part // 100`, division entière, et non `round()` :
celui de Python arrondit au pair le plus proche, si bien que 37,5 montait à 38
quand 112,5 descendait à 112 — deux écoles obtenaient des règles différentes sans
que rien ne le dise.

## Trois propriétés à ne pas lui retirer

- **idempotente** — `get_or_create` partout, et l'aléa dérive de l'identité des
  objets, jamais d'un compteur d'itération. Relancée, elle ne double rien ;
- **déterministe** — même graine, même école, jusqu'aux notes. Le tirage passe
  par `random.Random(chaîne)`, stable d'un processus à l'autre, et **jamais** par
  `hash()`, que Python randomise à chaque démarrage ;
- **refus hors développement** — elle crée des comptes à mot de passe connu et
  des écritures comptables. `--forcer` existe pour les bases jetables.

`apps/school/tests/test_doter_les_etablissements_reels.py` garde ces trois
propriétés en 39 tests, y compris l'idempotence par un second passage complet.

## Les volumes horaires tiennent dans la grille

Une classe a `len(JOURS) × len(CRENEAUX)` places par semaine — **36**. Le volume
suivait le coefficient et rien d'autre, et le programme en demandait jusqu'à
**74** pour une classe à 28 matières : l'emploi du temps se remplissait dans
l'ordre où les matières arrivaient, et les dernières n'obtenaient rien. Un
enseignant qui ne tenait que celles-là finissait l'année sans une heure.

La règle est celle d'un vrai conseil d'établissement : **une heure pour chacune
d'abord**, puis le reste aux plus forts coefficients. Et sur une base dont la
grille est déjà pleine, la dotation **retire le surplus** — jamais en dessous du
volume voulu, et seulement dans les classes qu'elle gère. Sans quoi elle ne
converge jamais : elle ne peut rien ajouter là où tout est pris.

## Le contrôle : `controler_la_dotation`

```bash
python manage.py controler_la_dotation
python manage.py controler_la_dotation --etablissement "IFP-OBK"
```

Il juge **dans le périmètre de la dotation, et pas au-delà** : les classes des
listes de `insert_classes`, sur l'année active. Une base vivante porte d'autres
classes — classes d'essai, élèves importés, année suivante préparée — et le
reprocher à la dotation serait faux.

D'où deux niveaux :

- les **erreurs** portent sur ce que la dotation garantit et sait corriger. La
  commande sort en échec, et un script d'un seul clic s'arrête là ;
- les **observations hors périmètre** signalent le reste sans échouer. Sinon la
  commande deviendrait impossible à satisfaire, et on prendrait l'habitude de
  l'ignorer.

Il vérifie la caisse, l'emploi du temps, l'encadrement, les bilans, les
familles, la discipline, les examens, le stock, le conseil — et les sept volets :
émargement et paie **par enseignant**, remise **par famille**, proportion
d'abonnés à la cantine, les trois niveaux du fonds numérique, et que la
passerelle SMS reste **inactive**.

## Les doublons de matières : `fusionner_les_matieres_en_double`

Une base sur laquelle on a travaillé des mois accumule les programmes. La classe
« 1ère Année TC » d'IFP-OBK portait « Mathématiques » **trois fois** (`MA-20`,
`MATH`, `MATH_CG`), « Anglais » deux fois, « Physique-Chimie » trois : 28
matières pour une dizaine de matières réelles.

Ce n'est pas qu'inélégant. Un bulletin imprime la même matière trois fois avec
trois moyennes, la moyenne générale la compte trois fois, et la grille horaire
s'épuise à placer des doublons au lieu du programme.

```bash
python manage.py fusionner_les_matieres_en_double              # simulation
python manage.py fusionner_les_matieres_en_double --appliquer   # exécution
```

**Elle supprime des matières et des notes**, donc la simulation est le mode par
défaut. Trois précautions de plus : elle ne touche qu'aux classes des listes sur
l'année active ; elle garde la matière du programme, seule à porter les notes de
**tous** les élèves ; et elle ne touche jamais à une matière seule de son nom.

**C'est une fusion, pas une suppression.** Une suppression sèche perdait 126
notes sans filet — des élèves n'avaient de moyenne dans cette matière que sur le
doublon. Les notes sans équivalent sont donc **déplacées** vers la matière
gardée ; seules les redondantes disparaissent.

## Ce qu'elle ne fait pas

- **Elle n'exécute pas le passage en classe supérieure.** Le conseil est simulé.
  Exécuter une promotion est une opération de fin d'année, qui change les classes
  de tous les élèves : elle se déclenche depuis l'application, par quelqu'un qui
  en décide.
- **Elle n'active pas la passerelle SMS.** La configuration existe pour que
  l'écran ait quelque chose à montrer ; `is_active` reste faux, et le jeton est
  manifestement faux, afin qu'aucun peuplement ne puisse faire partir un envoi.
- **Elle ne remplace pas `insert_classes`** : elle y lit la liste des classes,
  et ne devine jamais une école qu'elle ne reconnaît pas.

## Les comptes créés

| Rôle | Identifiant | Mot de passe |
|---|---|---|
| Directeur | `<code>.dir` | `Ecole@2026` |
| Censeur | `<code>.cen` | `Ecole@2026` |
| Comptable | `<code>.cpt` | `Ecole@2026` |
| Surveillant | `<code>.sur` | `Ecole@2026` |
| Promoteur | `<code>.pro` | `Ecole@2026` |

`<code>` est le code de l'établissement en minuscules (`lt`, `lo`, `if`, `cs`).

**Ces mots de passe sont connus.** La commande est faite pour une base de
développement ou de recette ; sur une base destinée à des utilisateurs réels,
changez-les à la première connexion.

## Le nom des deux écoles homonymes

« Lycée Technique Oumar Bah (LTOB) » et « Lycée Oumar Bah (LOBK) » sont deux
écoles distinctes. Elles se sont déjà confondues : le second avait reçu les cinq
classes du premier, alors qu'il en compte treize.

La commande rapproche donc une école de sa liste **par son sigle d'abord**,
l'égalité stricte ensuite, et l'inclusion de chaîne seulement si une seule école
répond. La migration `0070_le_lycee_oumar_bah_porte_son_nom` corrige le nom dans
les bases en place.
