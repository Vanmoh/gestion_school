# Les quatre écoles, décrites une seule fois

Elles l'étaient trois fois, et les trois descriptions ne concordaient pas.

| source | ce qu'elle créait |
|---|---|
| `9999_insert_etablissements` | Lycée Technique Oumar Bah (LTOB), Lycée Technique Oumar Bah (**LOBK**), IFP-OBK, Complexe Scolaire **Omar** Bah (CSOB) |
| `insert_etablissements` | LTOB, LOBK, IFP-OBK, Complexe Scolaire Oumar Bah |
| `insert_classes.ESTABLISSEMENT_CLASSES` | encore d'autres noms, plus une liste d'alias |

Un seul nom leur était commun : « IFP-OBK ». Enchaîner la migration et la
commande créait donc **sept établissements pour quatre écoles**. La commande
fusionnait ensuite ses alias et en supprimait trois — d'où quatre écoles portant
les identifiants 3, 5, 7 et 11, et une base où rien n'expliquait les trous.

Trois conséquences, toutes constatées :

1. **Une école invisible.** Les noms ont dérivé, et quelqu'un a saisi
   « LYCCE OBK » à la main. Aucune liste ne le reconnaissait :
   `controler_la_dotation` répondait « hors des listes de classes, non
   contrôlée » — et cette école n'a **jamais** été vérifiée. Ses 390 élèves, ses
   97 impayés, ses 43 fiches de paie : personne n'avait jamais regardé.
2. **Chaque base de test héritait de quatre établissements** qu'aucun test
   n'avait demandés. Un test qui en crée trois en compte sept, ce qui surprend
   au mieux et fausse un décompte au pire.
3. **Personne ne pouvait dire quel était le nom juste.**

## Trois identifiants, et à quoi sert chacun

`apps/school/etablissements_reels.py` les décrit désormais une seule fois.

- **`code`** (`LT`, `LO`, `IO`, `CS`) est le seul identifiant **stable**. Il est
  en base, il ne dérive pas, et il compose les matricules :
  `LT10CT25E0001M` commence par `LT`. **Il ne change jamais** — les matricules
  sont imprimés sur les cartes des élèves.
- **`sigle`** (`LTOB`, `LOBK`, `IFP-OBK`, `CSOB`) est la clé de
  `ESTABLISSEMENT_CLASSES`, donc ce qui relie une école à ses classes.
- **`nom`** est ce qu'un écran affiche. Il porte le sigle entre parenthèses,
  parce que `_classes_de` cherche d'abord un sigle entre parenthèses : c'est la
  seule chose qui distingue « Lycée Technique Oumar Bah (LTOB) » de
  « Lycée Oumar Bah (LOBK) ». Un nom sans sigle ne peut être rattaché que par
  égalité stricte, et la moindre faute de frappe le perd.

`NOMS_CONNUS` recense les noms qu'une base peut déjà porter — les deux listes
historiques, les variantes sans accent, et les saisies à la main constatées en
production, « LYCCE OBK » comprise. `code_de()` reconnaît une école par son code
d'abord, par son nom ensuite : **un nom peut mentir, un code non.**

## Les deux commandes, et pourquoi elles sont deux

- `insert_etablissements` **garantit** les quatre et **fusionne** les doublons,
  en faisant suivre les vingt-six clés étrangères avant de supprimer.
- `normaliser_les_etablissements` **renomme** et **renumérote**.

Les deux sont séparées à dessein : mêler renommage et fusion ferait qu'un simple
renommage pourrait supprimer une école.

## La renumérotation se demande

`--renumeroter` n'est pas actif par défaut, parce qu'il coûte quelque chose :
l'application garde l'école choisie en cache et l'envoie dans
`X-Etablissement-Id`. Après renumérotation, ce cache désigne une autre école ou
aucune — **chaque utilisateur doit rechoisir son établissement, une fois.**

Techniquement, déplacer un identifiant entraîne **26 clés étrangères et
23 107 lignes**. La manœuvre passe par un intervalle libre (`+1000`) puis
redescend chacun à sa place : passer directement #7 à #1 échouerait si #1 est
occupé par une école qui doit elle-même bouger. Le tout sous
`connection.constraint_checks_disabled()` — PostgreSQL diffère ses contraintes
jusqu'au commit, mais SQLite les vérifie à chaque instruction et refuserait le
premier déplacement — puis `check_constraints()` vérifie que rien ne pend dans le
vide.

Et `setval` recale la séquence : sans cela elle pointerait toujours au-delà de
#11, et la cinquième école créée porterait #12. Les trous reviendraient aussitôt.

## Pourquoi la migration ne pose pas les codes

`9999_insert_etablissements` sème par **nom seul**. `Etablissement.code`
n'existe pas encore à ce point du graphe : le champ arrive en `0047`, mais
`0011` et `0017` dépendent du semis — y ajouter une dépendance sur `0047`
créerait un cycle (Django le refuse, et le dit).

Ce n'est pas un manque. `0047` dérive le code des initiales des deux premiers
mots du nom, et les quatre noms canoniques donnent exactement `LT`, `LO`, `IO`,
`CS`. `test_etablissements_reels` le vérifie : **retoucher un nom canonique
changerait le code d'une école**, et donc les matricules de ses futurs élèves.

La migration recopie les noms au lieu de les importer, parce qu'une migration
doit se rejouer à l'identique dans dix ans alors que le module vivra. Le prix de
cette prudence est une duplication, et c'est un test qui la rend sûre.
