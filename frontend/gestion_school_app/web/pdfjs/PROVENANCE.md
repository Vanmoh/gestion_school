# pdf.js, versionné plutôt que récupéré à la volée

`pdf.min.js` et `pdf.worker.min.js` viennent de **pdfjs-dist 3.2.146**,
téléchargés une fois depuis `https://unpkg.com/pdfjs-dist@3.2.146/build/`.
Licence Apache-2.0 : voir `LICENSE` à côté.

    sha256  7662af706ecbf4ae9ba0f4f4ea50636617646c31d6c67aeca2338b1805a11c07  pdf.min.js
    sha256  4efa4f25d5f14e309922fb568e3b653ebc53cdb0d60b85bdefd22b30cb0a7a22  pdf.worker.min.js

## Pourquoi ces fichiers sont dans le dépôt

Le paquet `printing` va chercher pdf.js sur `unpkg.com` au premier aperçu, et
attend le chargement du script **sans délai maximal**
(`printing_web.dart`, lignes 70 à 113). Sur le serveur d'une école sans
Internet, ce script n'arrive jamais : l'attente ne se termine jamais non plus,
et l'aperçu tourne indéfiniment — bulletins, emploi du temps, listes de
classe, pièces jointes du chat. L'impression et le téléchargement, eux,
n'empruntent pas ce chemin et fonctionnaient déjà.

Les servir nous-mêmes est le seul moyen de fermer cette dépendance : la
neutraliser depuis Dart n'est pas possible, le CDN est une constante du
paquet.

## La version ne se change pas à la légère

`3.2.146` est celle que cible `printing` 5.14.3. L'API `getDocument` /
`GlobalWorkerOptions` de pdf.js 4.x n'est plus celle qu'appelle le plugin :
une mise à jour du fichier sans mise à jour du paquet casserait les aperçus,
en ligne comme hors ligne.

Les `cmaps/` ne sont volontairement pas embarqués : ils ne servent qu'aux PDF
à polices asiatiques, et les documents produits ici embarquent les leurs.

## Comment ils sont chargés

`web/index.html` pose deux verrous, et il en faut deux — voir le commentaire
sur place.
