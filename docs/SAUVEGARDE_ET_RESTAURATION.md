# Sauvegarde et restauration

Ce que l'application met dans une archive, ce qu'elle en laisse dehors, et
comment conduire l'opération. Écrit pour la personne qui exploite l'école,
pas pour le développeur.

## Ce que contient une archive

Une archive est un fichier `.zip` qui tient trois choses :

| Entrée | Contenu |
| --- | --- |
| `manifest.json` | Portée, date, auteur, options retenues, volume annoncé |
| `data.json` | Les données de la base, table par table |
| `media/…` | Les fichiers téléversés, si l'option a été cochée |

### Sauvegarde globale

Elle emporte **toute la base** : établissements, élèves, inscriptions,
notes, bulletins, absences, discipline, paiements, dépenses, salaires,
personnel, emplois du temps, bibliothèque, cantine, stock, messages,
journaux d'activité, et les comptes utilisateurs avec leurs mots de passe
sous forme hachée.

Trois tables techniques de Django restent dehors, parce qu'elles se
reconstituent seules et n'ont aucune valeur métier :

- les **types de contenu**, régénérés par les migrations ;
- les **sessions**, c'est-à-dire les connexions en cours, périmées en
  quelques heures ;
- le **journal de l'admin Django**, doublon des journaux d'activité, qui
  eux sont sauvegardés.

### Sauvegarde d'établissement

Elle ne prend que les lignes rattachées à l'école choisie, plus ses comptes
et ceux que ces lignes référencent. Un enseignant qui intervient dans deux
écoles est donc présent dans les deux archives.

Tout ce qui n'appartient à aucune école reste dehors : la personnalisation
de la plateforme, le fonds commun de la bibliothèque, les jetons de
notification.

### Jamais inclus

Le code de l'application, les migrations, les variables d'environnement et
les secrets. Une archive restaure des données, pas une installation. Pour
remonter un serveur entier, il faut redéployer puis restaurer.

## Les deux cases à cocher

**Inclure les médias.** Les fichiers téléversés : photos d'élèves, logos,
pièces jointes de discussion, justificatifs d'absence. Quelques mégaoctets
sur une école ordinaire.

**Inclure les documents de bibliothèque.** Le fonds d'annales et de manuels
importé. Décochée par défaut, et ce n'est pas un détail : sur une base
courante, ce fonds pèse plusieurs gigaoctets, soit à peu près mille fois le
reste des médias réunis. L'emporter à chaque sauvegarde rendait l'opération
si lourde qu'on ne la faisait plus — donc trop rare pour protéger quoi que
ce soit. Ces documents se réimportent sans perte :

```
manage.py import_bkalan
```

L'import rapatrie le fonds depuis sa source. Il se restreint à une série
avec `--serie`, et se contente du catalogue sans les fichiers avec
`--catalogue-seul`.

L'écran annonce le poids de chaque part avant de lancer, mesuré sur le
serveur. Une archive restaurée sans ces documents garde les fiches de la
bibliothèque ; seuls les fichiers eux-mêmes manquent, jusqu'au réimport.

## Suivre l'avancement

L'archive s'écrit dans un processus détaché : la demande rend la main tout
de suite, et l'historique affiche l'avancement. La ligne indique le
pourcentage, l'étape en cours, le volume déjà traité sur le volume total,
et une estimation du temps restant déduite du débit constaté.

La barre couvre les phases dans cet ordre : lecture de la base, écriture des
données, copie des médias fichier par fichier, puis calcul de l'empreinte de
contrôle. Les dernières fournées ne montent pas à 100 % tant que l'empreinte
n'est pas calculée : sur une grosse archive, ce calcul prend un moment et
l'écran ne doit pas annoncer « terminé » avant.

## Faire le ménage

Une sauvegarde hebdomadaire remplit le disque du serveur en quelques mois.
Deux gestes, réservés au super administrateur :

- **supprimer une archive**, depuis son icône dans l'historique, après une
  confirmation qui rappelle le poids libéré ;
- **nettoyer l'historique**, qui garde les archives les plus récentes et
  efface les autres. Le nombre à conserver se choisit dans la boîte de
  dialogue, et vaut trois par défaut.

Une opération en cours n'est jamais touchée : effacer un fichier en train de
s'écrire laisserait une archive tronquée et une ligne qui la réclame.

## Un point d'attention en production

Les médias sont lus sur le disque du serveur. Si l'installation utilise un
stockage objet (S3, Supabase), les fichiers n'y sont pas : la partie
`media/` de l'archive sera vide, quelle que soit la case cochée. Les données
de la base, elles, sont complètes dans tous les cas. Le stockage objet a sa
propre politique de versions et de rétention, à régler chez le fournisseur.

## Restaurer

La restauration **remplace** les données en place par celles de l'archive.
Ce qui a été saisi depuis la date de la sauvegarde est perdu. L'écran le
rappelle et demande confirmation nommée. Elle est réservée au super
administrateur, et suit le même affichage d'avancement.

Les fichiers médias déjà présents sur le serveur ne sont pas effacés : la
restauration recouvre ceux que l'archive contient et laisse les autres en
place. Une archive allégée ne fait donc pas disparaître la bibliothèque déjà
installée.
