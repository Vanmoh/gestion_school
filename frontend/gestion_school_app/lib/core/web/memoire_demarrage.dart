/// Ce que l'ecran de demarrage HTML a besoin de savoir avant Flutter.
///
/// `web/index.html` s'affiche pendant que le moteur se charge, donc avant
/// qu'une seule ligne de Dart ne s'execute. Il ne peut ni interroger l'API --
/// cela retarderait le premier trait -- ni lire le stockage des jetons, qui
/// est chiffre. L'application lui laisse donc, en clair et sous une cle a
/// elle, ce dont il a besoin pour se presenter: le nom de l'ecole, son logo,
/// son image de fond et sa couleur.
///
/// Rien au premier lancement: l'ecran garde ses libelles d'origine et son fond
/// dessine, et l'identite de l'ecole paraitra des la visite suivante.
library;

export 'memoire_demarrage_ailleurs.dart'
    if (dart.library.js_interop) 'memoire_demarrage_web.dart';
