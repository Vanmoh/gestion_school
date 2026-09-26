# La vidéo de démonstration des neuf rôles

Une vidéo d'environ neuf minutes qui parcourt l'application rôle par rôle, avec
chapitres, sous-titres et encadrés, sans voix ni musique. Elle se fabrique
**sur un runner GitHub**, jamais en local, et se publie en Release.

**Le lien à donner** — il pointe toujours vers la dernière version :

```
https://github.com/Vanmoh/gestion_school/releases/latest/download/demo_gestion_school.mp4
```

## Lancer une fabrication

Actions → « Publier la video de demonstration » → *Run workflow*. Trois
réglages, tous facultatifs :

| Entrée | À quoi elle sert |
|---|---|
| `duree_de_pose_ms` | Combien de temps chaque écran reste à l'image (2500 par défaut). Monter à 4000 donne une vidéo plus lente et plus longue. |
| `chapitres` | Les rangs à tourner, séparés par des virgules. `3` ne tourne que le directeur — c'est ce qu'on utilise pour éprouver une modification sans payer quarante minutes de runner. |
| `publier` | Décoché, le job garde les rushes en artefact sans créer de Release. |

Comptez **35 à 45 minutes** : deux minutes d'apt, deux de Flutter, trois de
peuplement, quatre pour le premier build CMake, dix-huit à vingt-cinq pour les
neuf prises, trois à cinq pour le montage.

## Pourquoi pas en local

La machine de développement n'a ni `ffmpeg`, ni `cmake`, ni `ninja`, ni
`pkg-config`, ni les en-têtes GTK, et il y reste un peu plus d'un gigaoctet de
mémoire libre — le build web l'avait déjà saturée. Rien de tout cela n'est un
obstacle sur un runner Ubuntu.

Ce qui **se vérifie quand même en local**, et qui couvre l'essentiel de ce qui
peut se tromper en silence :

```bash
# Le pilote compile et respecte les règles du dépôt
cd frontend/gestion_school_app && flutter analyze

# Le journal que le pilote écrit et que le montage relit
flutter test test/core/journal_de_demonstration_test.dart

# Le calcul du montage: horodatages, encadrés, chapitres, SRT
cd ../.. && python3 -m unittest discover -s tools/demo_video/tests

# Les cartons de titre, à regarder à l'œil
python3 tools/demo_video/monter_la_video.py --cartons-seulement --sortie /tmp/cartons

# Le décor et son garde-fou
cd backend && python manage.py test apps.school.tests.test_decor_de_demonstration
```

Seule la recette ffmpeg ne se vérifie qu'au premier tournage.

## Ce que le job ne peut pas faire

**Il ne peut pas atteindre la base de l'école.** Une vidéo se publie : filmer
des données réelles diffuserait les noms, matricules, notes, incidents et
dettes d'élèves mineurs, sans retour possible. Quatre barrières, dont trois
structurelles :

1. Le job déclare son **propre** service PostgreSQL et pose `DATABASE_URL` sur
   `localhost`. Il ne lit **aucun `secrets.*`** — contrairement au workflow de
   sauvegarde — et n'accepte **aucune entrée** d'URL, d'hôte ou d'identifiant.
   Il n'existe donc aucun chemin, même erroné, vers la production.
2. `seed_demo_data` refuse de semer hors développement, et refuse une base
   contenant des classes réelles. Le workflow ne passe pas `--forcer`.
3. `verifier_le_decor_de_demonstration` s'exécute **entre le peuplement et
   l'enregistrement** et fait échouer le job si un élève porte un nom qui
   n'appartient à aucune liste fictive connue, si un compte étranger au décor
   existe, ou si la base est trop maigre pour valoir le temps de runner. C'est
   la barrière qu'on peut voir échouer, et donc éprouver.
4. Le filigrane « DONNÉES FICTIVES — DÉMONSTRATION » est brûlé sur chaque image.

## Les pièces

| Chemin | Rôle |
|---|---|
| `.github/workflows/publier_video_demonstration.yml` | Le job : base jetable, peuplement, barrière, tournage, montage, Release |
| `tools/demo_video/enregistrer_les_chapitres.sh` | Serveur X, attente de la fenêtre, lecture de sa géométrie, capture, pilotage |
| `tools/demo_video/plan_de_montage.py` | **Pur, testé** : journaux → sous-titres, encadrés, chapitres |
| `tools/demo_video/monter_la_video.py` | Exécute le plan : Pillow pour les cartons, ffmpeg pour le reste |
| `frontend/.../integration_test/demonstration/pilote.dart` | Les gestes partagés par les neuf prises |
| `frontend/.../integration_test/demonstration/r*_test.dart` | Une prise par rôle |
| `frontend/.../lib/core/demonstration/journal_de_demonstration.dart` | Le canal entre le pilote et le montage |
| `backend/.../completer_le_decor_de_demonstration.py` | Ce qu'aucune commande de peuplement ne créait |
| `backend/.../verifier_le_decor_de_demonstration.py` | La barrière |

## Ce qui peut casser, et ce qu'on fait alors

**Le contexte OpenGL.** C'est le seul point qui peut condamner toute la voie :
l'embedder GTK de Flutter crée un contexte OpenGL, que Xvfb n'offre que par un
rendu logiciel. Le job le vérifie **en première étape** (`glxinfo -B`) et échoue
en cinq secondes plutôt que d'expirer au bout de dix minutes. Si cela arrive,
dans l'ordre : `LIBGL_ALWAYS_SOFTWARE=1` avec `+extension GLX` (déjà en place),
puis un gestionnaire de fenêtres minimal (openbox, déjà installé), puis Xephyr
ou weston en mode *headless*.

**Une prise qui échoue.** Elle ne fait pas tomber les huit autres : le montage
remplace le chapitre par un carton qui dit franchement qu'il manque. Les neuf
rushes et leurs journaux partent en artefact pendant cinq jours — sans eux, un
chapitre raté serait un mystère qu'on ne peut pas instruire.

**La fluidité.** En debug sous rendu logiciel, comptez 20 à 30 images par
seconde. La capture est donc réglée à 25, et on n'en promet pas plus. Passer en
`--profile` pour gagner en fluidité est impossible : la saisie de texte des
tests s'appuie sur une assertion qui n'existe qu'en debug.

**Le poids.** Le montage refuse au-delà de 150 Mo et propose alors le profil
`leger` (1024×576, 20 images/s), autour de 20 Mo pour un partage par messagerie.
Le profil `lisible` fait l'inverse : texte plus net, une centaine de mégaoctets.

**Une vidéo trop courte.** Le montage échoue sous une minute : cela signifie que
les prises ont sauté sans faire rougir le job, et publier ce fichier-là ne
tromperait que celui qui le télécharge.

## Modifier le scénario

Chaque rôle a son fichier `r<rang>_<role>_test.dart`. Les gestes passent par le
pilote, qui vise **des clés** et jamais des libellés : le nom d'une entrée de
menu change selon le rôle, et un pilote qui viserait le texte ouvrirait autre
chose d'un profil à l'autre.

Trois règles à ne pas enfreindre, sous peine de prises inexploitables :

- **Jamais `pumpAndSettle`.** La politique d'images `fullyLive` laisse tourner
  les animations : un indicateur de chargement ne s'arrête jamais, et l'attente
  irait jusqu'à l'expiration de la prise.
- **La frappe passe par `taperLentement`.** `enterText` pose la valeur d'un
  coup ; à l'image, le champ se remplit par téléportation.
- **Les encadrés passent par `souligner`**, qui journalise le rectangle réel du
  widget. C'est ce qui garde l'habillage juste quand une mise en page change.

Après modification : `flutter analyze`, puis un tournage du seul chapitre
concerné (`chapitres: 3`) pour regarder le rush avant de lancer les neuf.
