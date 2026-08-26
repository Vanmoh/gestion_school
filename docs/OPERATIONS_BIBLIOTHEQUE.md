# Bibliothèque numérique — exploitation

Le fonds documentaire (annales et brochures BKalan, ~1257 PDF rangés en
9 séries) vit en deux temps volontairement séparés : le **catalogue**, qui
suffit à rendre l'écran utilisable, et le **rapatriement**, qui rend
l'application indépendante de `bkalan.ml`.

## 1. Le catalogue — automatique

`backend/entrypoint.sh` **confie le catalogage au worker Celery** à chaque
démarrage du conteneur API :

```sh
timeout 60 python manage.py queue_library_catalogue
```

Le service web ne lit plus les neuf pages de bkalan.ml lui-même : il dépose un
message dans la file et rend la main. La source peut être lente ou muette,
cela ne coûte plus le temps de personne — le worker, lui, ne sert aucune
requête HTTP.

Les garde-fous :

- **rien de bloquant** : un courtier injoignable laisse le catalogue vide,
  l'API relaie alors la source, et le service démarre normalement ;
- **`--si-vide` implicite** : la tâche s'arrête avant tout appel réseau si le
  fonds est déjà catalogué. L'entrypoint est rejoué à chaque *réveil*, pas
  seulement à chaque déploiement ;
- **catalogue seul** : aucun PDF n'est téléchargé ici. Voir §2 ;
- **un filet planifié** : `CELERY_BEAT_SCHEDULE` repasse chaque nuit à 3h15,
  ce qui rattrape le cas où le courtier était injoignable au démarrage.

Pour relancer un catalogage à la main, sans attendre :

```sh
python manage.py queue_library_catalogue --forcer
```

Tant qu'un document n'est pas rapatrié, `GET /api/library-documents/{id}/file/`
relaie la source. Le mode hybride est invisible côté client.

**Couper l'appel à la source** : `LIBRARY_AUTO_IMPORT=False` dans les variables
du service (déclarée dans `render.yaml`).

**Vérifier après un déploiement** : les logs Render du service API portent
une ligne `10-eme-CG: N documents, M matieres` par série,
suivie de `Catalogue: N documents references.` ou
`Catalogue deja en place: rien a faire (--si-vide).` aux démarrages suivants.
En cas d'échec, la ligne `Bibliotheque: catalogue non importe (...)` le dit —
le service reste sain, et un simple redémarrage retente.

## 2. Le rapatriement — manuel, une fois

Volontairement hors du démarrage : plusieurs gigaoctets, à écrire dans le
bucket objet.

### Ce que pèse le fonds

Mesuré en sondant la source (échantillon de 120 documents, `Content-Length`) :

| Tranche | Documents | Volume |
| --- | --- | --- |
| ≤ 5 Mo | ~1076 (86 %) | **0,93 Go** |
| ≤ 10 Mo | ~1132 (90 %) | 1,38 Go |
| Fonds entier | 1257 | **~6,4 Go** |

Taille moyenne 5,2 Mo mais **médiane 0,9 Mo** : une centaine de gros fichiers
— jusqu'à 127 Mo pièce — portent presque tout le volume. D'où la stratégie à
deux vitesses ci-dessous.

### Deux déploiements, deux périmètres

- **Installation locale de l'école** : le fonds entier, le disque n'est pas
  compté.

  ```sh
  python manage.py import_bkalan --jobs 8
  ```

- **Production Render + Supabase** : seulement la partie légère, qui tient
  dans le plan gratuit du stockage objet. Les documents au-delà du seuil
  restent relayés depuis la source — le mode hybride est invisible côté
  client.

  ```sh
  python manage.py import_bkalan --taille-max 5 --jobs 8
  ```

`--taille-max` sonde le poids annoncé (une requête HEAD) avant de télécharger,
et coupe le transfert au seuil si la source ne l'annonce pas. Un document
écarté **n'est pas noté en erreur** : il reste rapatriable, et une exécution
ultérieure sans seuil le prendra.

Le service tourne en `plan: free`, qui n'ouvre pas de shell Render. La
commande se lance donc **depuis le poste**, pointée sur la base et le bucket
de production (`DATABASE_URL` Supabase + les quatre variables `AWS_*`, cf.
`prepare_supabase_render_env.sh`) :

```sh
python manage.py import_bkalan            # catalogue + fichiers manquants
python manage.py import_bkalan --limit 50 # une première tranche, pour voir
python manage.py import_bkalan --serie TSExp
python manage.py import_bkalan --jobs 8   # plus de téléchargements en parallèle
```

Sur un plan payant, le shell Render du service `gestion-school-api` fait
aussi bien, et évite de faire transiter les fichiers par une liaison locale.

La commande est **rejouable** : `source_url` porte l'unicité, une seconde
exécution ne crée aucun doublon et ne retélécharge que ce qui manque. Un
fichier déjà rangé au bon endroit dans le stockage est adopté tel quel, même
si la base ne le connaît plus — les media survivent souvent à la base.

Le rapatriement vers Supabase n'a de sens **que si `AWS_STORAGE_BUCKET_NAME`
est renseigné** : le disque du conteneur Render est éphémère, et les fichiers
disparaîtraient au déploiement suivant (l'API retomberait alors sur le relais,
sans erreur visible, mais le travail serait à refaire).

## 3. Servir les PDF sans les faire transiter par Render

`LIBRARY_STORAGE_REDIRECT=True` fait répondre l'API par une **redirection vers
une URL signée** du bucket, au lieu de relayer le fichier. Un document de
40 Mo cesse alors de traverser un conteneur qui ne dispose que de 0,1 CPU et
512 Mo.

**Désactivé par défaut, et pas par excès de prudence** : sur le web,
l'application lit ce fichier en XHR. Une redirection vers un autre domaine
déclenche un contrôle CORS côté bucket. Tant que le bucket n'accepte pas
l'origine de l'application, activer ce réglage **casse l'ouverture des
documents dans le navigateur** — sans rien casser sur Android ni sur le poste,
où le CORS n'existe pas.

Marche à suivre :

1. Dans Supabase, autoriser l'origine `https://gestion-school-web.onrender.com`
   sur le bucket (méthode `GET`, en-tête `Range` inclus pour que la lecture
   partielle d'un PDF fonctionne).
2. Vérifier depuis le navigateur qu'un document s'ouvre encore.
3. Seulement ensuite, poser `LIBRARY_STORAGE_REDIRECT=True` dans les variables
   du service.

Trois garde-fous dans le code, tous nécessaires : le réglage doit être actif,
le stockage doit rendre une URL absolue (un stockage sur disque rend un chemin
relatif, qui ne redirige nulle part), et cette URL doit être **signée** — une
URL nue resterait ouverte à qui l'a vue passer. Si l'une manque, l'API sert le
fichier elle-même, comme avant.

La durée de cache de la redirection est calée sur `AWS_QUERYSTRING_EXPIRE` :
garder l'adresse plus longtemps que sa signature mènerait à un 403.

## 4. Ce que l'API fait des relectures

`GET /api/library-documents/{id}/file/` porte un `ETag` et un `Cache-Control`.
Un document déjà lu revient en **304 sans corps** : ni le stockage ni la
source ne sont sollicités. L'empreinte inclut `is_downloaded`, si bien qu'un
document qui passe du relais au stockage périme automatiquement la copie du
client.

Le relais lit par blocs de 64 Ko et transmet le `Content-Length` de la source,
sans quoi l'application n'a aucune fin à annoncer pendant le téléchargement.
Les PDF échappent volontairement à la compression (`apps.common.middleware`) :
un PDF ne se compresse pas, et gzip aurait supprimé ce `Content-Length`.

## 5. Les 43 documents morts à la source

43 des 1257 documents répondent 401 sur le serveur de BKalan, quel que soit
l'encodage tenté. Ils sont catalogués et portent leur `import_error` : les
taire les ferait passer pour des téléchargements en attente.

```sh
python manage.py shell -c "
from apps.school.models import LibraryDocument
for d in LibraryDocument.objects.exclude(import_error=''):
    print(d.import_error, d.source_url)"
```

`--retenter-erreurs` les remet dans la file si la source se répare un jour.

## 6. Les documents déposés par un établissement

À côté du fonds importé, chaque école pose ses propres étagères depuis
l'écran : bouton « Ajouter un document » de l'onglet « Documents ». Rien à
exploiter côté serveur, mais deux règles à connaître quand un utilisateur
appelle.

**Ce qui est cloisonné.** Une série créée depuis l'application porte un
`etablissement` ; le fonds importé, non. Chacun voit le fonds commun **plus**
ses propres documents, jamais ceux d'une autre école. Les fichiers déposés
sont rangés sous `library_docs/etab_<id>/…`, ce qui laisse deux écoles
nommer leur série « Documents » et y déposer chacune un `reglement.pdf`.

**Ce qui est refusé, et pourquoi.**

| Message | Cause |
| --- | --- |
| « Le fonds commun ne peut pas être alimenté depuis l'application » | La matière visée appartient au fonds importé. Il ne s'alimente que par `import_bkalan`, et une modification serait écrasée à la passe suivante. |
| « Seuls les fichiers PDF sont acceptés » | Extension autre que `.pdf`. |
| « Ce fichier n'est pas un PDF valide » | L'extension est bonne mais les cinq premiers octets ne sont pas `%PDF-`. C'est la signature qui fait foi : on renomme un exécutable en `.pdf` en deux secondes. |
| « Fichier trop volumineux » | Au-delà de `LIBRARY_UPLOAD_MAX_MB` (50 Mo par défaut). Le fonds importé monte jusqu'à 127 Mo par document, mais il n'entre pas par cette porte. |

**Qui peut déposer.** La matrice de `apps/accounts/access.py` : écriture sur
`library` pour l'administration et le surveillant, suppression pour la seule
administration. L'élève et le parent lisent.

Supprimer un document efface aussi son fichier du stockage ; remplacer le
fichier d'un document efface l'ancien. Les documents importés, eux, ne se
suppriment ni ne se renomment depuis l'application.

## 7. Fonds papier

Sans rapport avec ce qui précède : `Book` et `Borrow` sont cloisonnés par
établissement et se saisissent depuis l'onglet « Ouvrages » du module.

**Les exemplaires se comptent tout seuls.** `quantity_available` est dérivé
— total moins les emprunts non rendus — et n'est plus saisi ni accepté en
écriture par l'API. Un prêt le fait baisser, un retour le fait remonter. Si
un compteur paraît faux (import manuel en base, suppression directe d'un
emprunt), `Book.recalculer_disponibilite()` le remet d'aplomb sans rien
recalculer d'autre.

**Rendre un ouvrage** : `POST /api/borrows/<id>/return/`, avec deux champs
facultatifs — `returned_at` (défaut : aujourd'hui, pour saisir lundi un
livre rendu vendredi) et `penalty_amount` (impose un montant à la place du
calcul). Rendre deux fois le même emprunt est refusé : sans ce garde-fou, le
compteur d'exemplaires remonterait au-delà du fonds réel.

**La pénalité de retard** vaut `library_penalty_per_day` de l'établissement
multiplié par les jours entamés au-delà de l'échéance. Le tarif se règle sur
la fiche établissement (champ « Penalite retard / jour ») et vaut **0 par
défaut** : aucune école ne voit apparaître de pénalité qu'elle n'a pas
demandée. `penalty_due` sur la ligne d'emprunt montre ce que le retard
coûterait aujourd'hui, `penalty_amount` ce qui a réellement été porté au
dossier au retour.

**La fiche accepte quatre compléments facultatifs** — matière, éditeur,
année d'édition et cote (« Étagère B3 ») — vides sur tout l'existant. La
recherche du catalogue les couvre, au même titre que le titre, l'auteur et
l'ISBN.

**L'ISBN est unique par établissement**, plus globalement : deux écoles
possèdent le même manuel. Un doublon dans la même école est refusé avec un
message sur le champ `isbn`, pas par une erreur d'intégrité.
