# Écrans publics — ce qui se règle, et où

L'écran de démarrage, le portail de sélection et l'écran de connexion se
suivent dans le parcours :
on choisit son école, puis on s'y connecte. Ils partagent donc le même fond,
la même police de titre, la même salutation et le même pied de page. Ce qui
suit vaut pour les deux.

## 1. L'image de fond de la plateforme

**Écran Personnalisation → « Choisir une image de fond ».**

Elle habille **le portail et la connexion**, sous un voile sombre. C'est
l'image de la plateforme, celle qui vaut avant qu'un établissement soit
choisi — le portail précède ce choix, il ne peut donc afficher que celle-ci.

PNG ou JPEG, large plutôt que haute, 1600 px au minimum, **6 Mo au plus** :
au-delà, chaque ouverture du portail la retélécharge, le serveur d'école
répondant `no-store`.

## 2. La photo d'accueil d'un établissement

**Écran Établissements → « Choisir photo d'accueil »**, à côté du logo.

**Elle prime sur l'image de la plateforme** une fois l'école choisie : on est
alors chez un établissement précis, et sa façade parle mieux que l'image
commune. Elle occupe la partie gauche de l'écran de connexion sur ordinateur
— celle qui porte la marque — et toute la page sur téléphone. Elle est toujours
recouverte d'un voile sombre et se fond vers la droite : sans lui, le texte
posé dessus deviendrait illisible, et les photos d'école sont prises à toute
heure, donc de luminosité imprévisible. La carte de connexion, elle, reste sur
le fond sombre : du texte de saisie sur une photo se lit mal, même voilée.

**Ce qui fait une bonne photo** : la façade, la cour, une salle de classe.
Large plutôt que haute, 1600 px de large au minimum. Évitez les photos très
claires ou très chargées au centre gauche, où se posent le nom et le logo.

Facultative : sans elle, l'écran garde son fond dessiné (dégradé et halos),
qui ne coûte aucun téléchargement.

Champ `cover_image` sur `Etablissement`, migration
`0056_photo_de_couverture`. Distinct du logo, qui est un dessin cadré serré
sur fond blanc et qu'on ne peut pas étaler en pleine page.

## 3. Le logo

Même écran, bouton « Choisir logo ». Il s'affiche sur une plaque claire
arrondie : la plupart des logos d'école sont dessinés en noir sur fond blanc,
et posés à nu sur une page sombre ils formaient un rectangle blanc franc — une
tache, pas une marque.

Sur téléphone et dans la carte, c'est la pastille d'identité qui prend le
relais : le logo y serait trop petit pour être lu, et les initiales sur
dégradé distinguent mieux deux écoles.

## 4. Les phrases d'accueil

**Écran Personnalisation**, champs « titre connexion » et « sous-titre
connexion ». Le sous-titre remplace la phrase par défaut :

> Notes, emplois du temps, paiements et bulletins : tout l'établissement dans
> un seul espace.

Écrivez ce que votre école veut annoncer — c'est la seule ligne de la page qui
dit à quoi l'on accède.

## Ce que l'écran fait tout seul

- **Salutation et date** sur les deux écrans : « Bonjour / Bon après-midi /
  Bonsoir », suivi du jour en toutes lettres. Elle dit au passage que le poste est à l'heure, ce
  qui n'a rien d'acquis sur une machine restée éteinte des semaines.
- **Couleur** : tout l'écran suit l'accent réglé dans Personnalisation.
- **Réglages techniques** (adresse de l'API, test de connexion, changement
  d'établissement) : derrière l'icône en coin. Ils reparaissent d'eux-mêmes
  sous le formulaire quand le serveur est injoignable — le seul moment où ils
  servent.
- **Mot de passe oublié** : affiche la marche à suivre et les coordonnées de
  l'école. Le serveur n'offre aucune réinitialisation en libre-service ; seule
  l'administration fixe un mot de passe provisoire, depuis l'écran
  Utilisateurs.
- **Mouvement réduit** : si le système le demande, halos figés, apparitions
  instantanées, aucun fondu.

## Pourquoi les tuiles du portail restent multicolores

Chaque établissement y porte sa propre teinte (violet, cyan, vert, ambre),
alors que tout le reste des deux écrans suit l'accent réglé dans
Personnalisation. Ce n'est pas un oubli d'uniformisation : ces teintes se
déduisent de l'identifiant de l'école et servent à les distinguer d'un coup
d'œil quand plusieurs ont un logo générique. Les uniformiser rendrait la
grille lisible mais indifférenciée.

## L'écran de démarrage

C'est le premier écran, affiché pendant que le moteur se charge. Ce n'est pas
un écran Flutter mais du HTML, dans `web/index.html` : il s'affiche donc avant
qu'une seule ligne de code applicatif ne s'exécute.

**Il porte votre identité dès la deuxième ouverture.** Il ne peut pas
interroger le serveur — cela retarderait le premier trait — ni lire le
stockage des jetons, qui est chiffré. L'application lui laisse donc, dans une
clé du navigateur écrite en clair (`gs.marque`), ce dont il a besoin : le nom
de l'école, son logo, son image de fond et sa couleur d'accent. Rien n'y est
confidentiel : ce sont les informations que la page d'accueil affiche déjà.

Conséquence à connaître : **au tout premier lancement sur un poste**, ou après
un effacement des données du navigateur, l'écran garde ses libellés d'origine
(« Gestion School ») et son fond dessiné. L'identité paraît à l'ouverture
suivante. C'est le prix d'un démarrage qui n'attend aucun réseau.

Il partage le reste avec les autres écrans : les couleurs du thème sombre, les
polices Inter et Sora, et une sortie en fondu de 260 ms enchaînée par
l'application dès sa première image.
