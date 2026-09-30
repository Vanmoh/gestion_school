# Ce qui appartient à une année scolaire

Une école ne vit pas une seule année. Dès qu'une deuxième existe en base, toute
liste qui ne dit pas de quelle année elle parle devient un comptage faux — et un
comptage faux est plus difficile à repérer qu'une erreur, parce que rien ne
s'affiche de travers.

IFP-OBK a ouvert sa seconde année. Son directeur lisait **611 élèves** pour 450
inscrits et **544 matières** pour 297, sans qu'aucun écran ne signale que les
deux années étaient additionnées.

Ce document dit qui doit porter l'année, qui ne doit pas, et comment le
rattachement se fait quand personne ne l'a posé.

## Trois familles, et une seule règle par famille

### 1. Ce qui appartient à une année, et n'est lu que par année

Vingt-cinq vues portent `AnneeScolaireScopeMixin` et filtrent sur l'année
demandée : classes, matières, affectations, créneaux, élèves, notes, absences,
pointages, discipline, barèmes, frais, paiements, dépenses, paie, emprunts,
cantine, sessions et résultats d'examen, publications.

Le rattachement passe soit par un champ `academic_year` direct, soit par une
chaîne déclarée — `academic_year_field = "session__academic_year"` pour un
résultat d'examen, `"assignment__classroom__academic_year"` pour un créneau.

### 2. Ce dont le métier est justement de traverser les années

`StudentAcademicHistory` est le **parcours** d'un élève : plusieurs années par
construction, et sa vue ordonne d'ailleurs par `-academic_year_id`. L'écran
« Dossier élève » l'appelle sans préciser d'année — mais l'en-tête global en
ajoutait une, et le parcours se réduisait à l'année active. Sur IFP-OBK, 502
bilans sur 1 893 disparaissaient : un redoublant ne voyait plus d'où il venait.

Ces vues gardent le mixin et posent `academic_year_filtre_la_liste = False`. La
protection des années closes reste, le `?academic_year=` explicite reste ; seule
la restriction **implicite** tombe.

`PromotionRun` relève du même principe pour une autre raison : il relie
`source_academic_year` à `target_academic_year`. Le filtrer sur l'année active
masquerait précisément le passage qu'on vient de faire. Il ne porte donc pas le
mixin, et c'est voulu.

### 3. Ce qui n'appartient à aucune année

Un livre, un fournisseur, un article de stock, un enseignant, un parent, un menu
de cantine : ils traversent les années sans leur appartenir. Leur donner une
année serait recopier la même ligne chaque septembre.

## Le champ facultatif est un piège, et voici lequel

Quatre modèles acceptent un `academic_year` vide : `Attendance`,
`DisciplineIncident`, `Expense`, `TeacherPayroll`. Le champ a été rendu
facultatif pour ne pas casser les lignes antérieures à son introduction.

C'est cette tolérance qui se retourne contre nous. Le filtre demande
`academic_year=<année>`, et **`NULL` ne répond pas à ce filtre**. Comme
l'application envoie l'en-tête d'année sur *toutes* ses requêtes, une ligne sans
année ne s'affiche jamais — on ne peut donc pas la corriger, faute de la voir.
Quarante-quatre lignes de la base réelle étaient dans ce cas : 9 absences,
1 incident, 10 dépenses et 24 fiches de paie.

**La date, elle, est toujours là.** Et deux années d'un même établissement ne
peuvent pas se chevaucher — `AcademicYear.clean` et
`AcademicYearSerializer.validate` le refusent tous deux. Une date désigne donc
**au plus une** année : le rattachement est déductible.

`apps/school/rattachement_a_l_annee.py` le déduit, et quatre `pre_save` le
branchent sur les quatre modèles. Un `pre_save` et non le serializer, parce que
le serializer ne couvre que l'API : les commandes de peuplement, l'admin et les
migrations écrivent par le modèle, et c'est par là que les quarante-quatre
orphelines sont entrées.

Deux choses qu'il ne fait pas, volontairement :

- **Il ne devine pas.** Établissement inconnu, ou aucune année ne couvre la
  date — une dépense d'août, une paie de juillet : la ligne reste sans année.
  C'est exact, et non un oubli. Mieux vaut une ligne orpheline, qu'une requête
  retrouve, qu'une ligne rangée dans la mauvaise année, qui faussera un bilan
  sans jamais se signaler.
- **Il ne corrige pas.** Une année déjà posée n'est jamais remplacée : une
  absence rattachée à la main est peut-être une décision de la direction, et ce
  n'est pas à un `pre_save` d'en juger.

## Une liste se filtre, une identité non

`filter_queryset` sert la liste **et** le détail : DRF l'appelle depuis
`get_object`. C'est ce qui a permis d'appliquer l'année à vingt-cinq vues sans
toucher à des `get_queryset` à douze points de retour — mais cela mélange deux
questions différentes.

`Student.classroom` ne contient que la classe **actuelle**. Un élève promu de
6ème en 5ème n'a donc plus aucun lien avec l'année passée. Le filtrer par
l'année choisie le fait disparaître entièrement — et avec lui
`/students/<id>/dossier/`, qui est justement l'écran qu'on ouvre pour regarder
le passé. La direction lisait 404 sur un élève inscrit.

D'où `academic_year_filtre_le_detail`, posé à `False` sur `StudentViewSet` seul.
La liste reste filtrée : « qui est dans une classe de cette année » est une
question légitime, et c'est elle qui a corrigé les 611 élèves lus pour 450.

L'élève est le seul cas, parce qu'il est la seule entité dont l'identité
survit à l'année tandis que son champ de rattachement ne pointe que sur le
présent. Une classe, une matière, un créneau appartiennent à une année par
construction.

## Les agrégats ne passent pas par le filtre

Une action personnalisée qui agrège sur `self.get_queryset()` contourne
`filter_queryset`, donc l'année, **en silence**. Et un agrégat faux ne se voit
pas : dans une liste on reconnaît les intrus, pas dans un total.

Deux l'ont payé :

- `students/stats` annonçait « 2025-2026 : 611 élèves » sur une année qui en
  comptait 450. Le décompte ignorait l'année tandis que l'étiquette l'affichait.
  Un chiffre faux portant le nom de la bonne année trompe davantage qu'un
  chiffre sans étiquette : rien n'invite à le vérifier. La carte **nomme** une
  année, donc elle doit compter celle-là — le filtre y est posé explicitement,
  et non laissé à `_filtrer_par_annee` qui n'agit que si l'en-tête est présente.
- `teacher_workload` additionnait les créneaux des deux années : 478 h au total
  là où il y en a 453 pour 2025-2026 et 25 pour 2026-2027. Trois enseignants
  présents dans les deux paraissaient faire le double de leurs heures — et c'est
  ce chiffre que la direction lit pour arbitrer les services. `export_excel`
  sortait de même trente onglets pour quinze classes, dans un fichier qu'on
  imprime et qu'on distribue.

Restent bornées par une date, ce qui suffit : `payments/totaux` (un total de
caisse répond à « ce qui est entré ce mois-ci », pas à une année),
`monthly_stats`, et `generate_monthly` pour la paie — dont les heures
attribuées se déduisent des dates de l'année, ce qui ne tient que parce que
deux années ne peuvent pas se chevaucher.

**Règle :** une action qui agrège sur une vue à portée d'année doit appliquer
`self._filtrer_par_annee(...)`, ou se borner explicitement par une date.

## Deux couches de portée, et la ligne qui passe entre elles

L'établissement et l'année ne se rejoignent pas toujours par le même chemin. Sur
`ExamResult`, la portée d'établissement passe par `student__etablissement` et
celle de l'année par `session__academic_year`.

Trois notes de la base réelle en profitaient : deux élèves du Lycée Technique et
une du Complexe Scolaire portaient un résultat sur une session « Examen Blanc
T1 » appartenant à IFP-OBK. Chaque couche était cohérente de son côté, et la
ligne se glissait entre les deux — visible dans la liste de son école, exclue dès
que l'année entrait en jeu.

Ce n'est pas qu'un défaut d'affichage : la moyenne d'une classe, le rang et le
bulletin se calculent sur ces lignes. `_ne_noter_que_ses_propres_eleves` refuse
désormais l'attelage.

**La règle générale :** quand deux portées atteignent l'établissement par deux
chemins différents, il faut une garde qui dise qu'ils désignent le même. Sans
elle, chaque filtre a raison séparément et l'ensemble a tort.

## La promotion : « différente » n'est pas « suivante »

`PromotionRun` est la seule opération dont le métier est de traverser les
années. Elle vérifiait que l'année cible existe et qu'elle **diffère** de la
source — et « différente » laisse passer le passé.

L'écran choisit sa cible en prenant une autre année que la source, dans une
liste triée par `-is_active, -start_date`. Tant qu'une école n'a que l'année
courante et la suivante, cela tombe juste. Dès sa première promotion elle aura
une année passée, et c'est celle-là qui sera proposée.

Or une promotion s'applique : elle réaffecte `Student.classroom` et écrit dans
`StudentAcademicHistory`. Renvoyer une cohorte entière dans l'année d'avant ne
se défait pas d'un clic. D'où la garde sur `start_date`.

L'établissement, lui, n'avait pas besoin de garde : les classes source **et**
cible sont déjà filtrées par établissement dans `_resolve_source_classrooms` et
`_resolve_mapping`. Passer l'année d'une autre école ne produit donc qu'un
traitement vide — gênant, mais sans écriture.

## Le pire cas : une année fausse sur un document imprimé

`_active_academic_year_label()`, dans `apps/reports`, ne prenait aucune portée.
Sans portée, `AcademicYear.courante(None)` rend `filter(is_active=True)` trié
par `-start_date` : l'année active de **n'importe quelle** école, en pratique
celle qui a commencé le plus tard. Mesuré sur la base réelle, l'appel rendait
l'année du Complexe Scolaire à qui la demandait.

Cinq endroits l'appelaient : la carte scolaire (libellé **et** date de
validité), le certificat de fréquentation, la vérification d'une carte, et deux
rendus de carte.

Le défaut est invisible aujourd'hui, parce que les quatre écoles nomment toutes
leur année « 2025-2026 » : le mauvais choix rend le bon libellé. Il se
déclenchera le jour où l'une ouvre 2026-2027 en active — et il se déclenchera
sur du papier remis à une famille, que personne ne peut plus corriger.

C'est le pire cas de cette famille de défauts, et il tient en une règle : **une
année ne se résout jamais sans dire de quelle école.** Les tests de
`test_l_annee_imprimee_est_celle_de_l_ecole.py` donnent pour cette raison des
noms d'année *différents* aux deux écoles — un test où les deux s'appellent
pareil ne peut rien voir, ce qui est exactement ce qui a laissé le défaut vivre.

## Un orphelinat plus profond : sans école, pas d'année

En comblant les années, dix dépenses d'avril 2026 n'avaient pas bougé. Leur date
tombait pourtant en pleine année scolaire — mais leur `etablissement` était
`NULL`. Sans école, pas d'année : le rattachement ne peut pas se déduire, et il
ne devine pas.

Ces dix lignes étaient donc invisibles **deux fois** : absentes de la liste de
chaque école, et absentes de chaque année. 1 200 000 F de charges qu'aucun écran
ne montrait et qu'aucune trésorerie ne comptait.

Rien ne les distinguait les unes des autres — même libellé « Achat fournitures »,
même montant, même catégorie, dates consécutives. Aucune règle ne pouvait dire
laquelle appartient à quelle école, et
`repartir_les_depenses_sans_ecole` ne le prétend pas : elle répartit à tour de
rôle, chacune rattachée à l'année active de l'école qui la reçoit. C'est un choix
assumé, pas une déduction — `--etablissement` permet de tout donner à une seule
école quand la comptabilité sait mieux. Appliqué : IO 3, LT 3, LO 2, CS 2.

Seules les écoles qui **ont** une année active sont candidates. Une école sans
année ouverte ne peut pas recevoir une charge datée : la dépense deviendrait
visible dans sa liste mais resterait hors de toute année — à moitié rangée, ce
qui ne vaut pas mieux qu'orpheline. Et il en existe : la migration
`9999_insert_etablissements` crée les quatre écoles réelles, et une base neuve
les porte sans année.

## Ce qui n'a rien à assurer ne se pointe pas

Vingt pointages et quatorze émargements appartenaient à un enseignant sans
aucune matière. Depuis `_ne_pointer_que_ceux_qui_enseignent`, la base refuse d'en
créer — mais les lignes antérieures à la règle restaient, et elles faussaient
trois calculs : la charge horaire, la concordance, et la paie, puisque
`_teacher_hours_worked` comptait des heures travaillées sur des séances qui
n'avaient jamais existé.

`controler_la_dotation` les signalait sans pouvoir les corriger, et son conseil
« relancez la dotation » ne s'appliquait pas : la dotation ne connaît pas ces
enseignants. `retirer_les_pointages_sans_matiere` est le remède manquant.

Elle ne touche pas aux enseignants eux-mêmes —
`retirer_les_enseignants_sans_matiere` s'en occupe, et c'est une décision
séparée : un enseignant sans matière cette année peut en reprendre une la
prochaine.

## L'en-tête n'est plus une condition

`AnneeScolaireScopeMixin` ne filtrait **que si** le client envoyait
`X-Academic-Year-Id`. Sa docstring l'expliquait : « la bascule arrive écran par
écran sans casser les autres ». C'était un bon plan de transition.

La bascule est finie — les vingt-cinq vues portent le mixin — mais la
permissivité était restée : sans en-tête, l'API rendait encore 611 élèves et 544
matières. L'application envoie l'en-tête, donc elle ne voyait rien ; un export,
un script, ou un écran qui interroge avant que l'année soit chargée le voyaient.

Le filtre retient désormais l'année demandée, **à défaut l'année active de
l'établissement consulté**. Mesuré : `/students/` rend 450 sans en-tête comme
avec.

Une exception, et une seule : un appel qui ne désigne **aucun** établissement
n'est pas filtré. `AcademicYear.courante(None)` rend `filter(is_active=True)`
trié par `-start_date`, c'est-à-dire l'année active de n'importe quelle école.
Replier là-dessus filtrerait les quatre établissements sur l'année d'un seul —
pire que ne pas filtrer. C'est la même règle que partout ailleurs dans ce
document : **une année ne se résout jamais sans dire de quelle école.**
