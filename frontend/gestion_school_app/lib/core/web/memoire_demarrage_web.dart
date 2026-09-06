/// Mise en oeuvre web: deux echanges avec `web/index.html`.
library;

import 'dart:convert';
import 'dart:js_interop';

/// La cle est prefixee `gs.` et ecrite en clair: `index.html` doit pouvoir la
/// lire d'un seul appel synchrone, avant tout rendu. Elle ne contient que ce
/// qu'un visiteur de la page d'accueil voit deja -- le nom de l'ecole, son
/// logo, son image de fond, sa couleur. Le stockage des jetons, lui, reste
/// chiffre et hors de portee d'un script.
const String _cleMarque = 'gs.marque';

@JS('window.localStorage.setItem')
external void _ecrire(String cle, String valeur);

@JS('window.localStorage.removeItem')
external void _effacer(String cle);

@JS('window.__hideBootStatus')
external JSFunction? get _masquerLeDemarrage;

void memoriserLaMarque({
  required String nomEcole,
  required String nomApplication,
  required String logoUrl,
  required String imageFondUrl,
  required String couleur,
}) {
  try {
    final marque = <String, String>{
      'nom': nomEcole.trim().isEmpty ? nomApplication.trim() : nomEcole.trim(),
      'logo': logoUrl.trim(),
      'fond': imageFondUrl.trim(),
      'couleur': couleur.trim(),
    };
    if (marque.values.every((valeur) => valeur.isEmpty)) {
      _effacer(_cleMarque);
      return;
    }
    _ecrire(_cleMarque, jsonEncode(marque));
  } catch (_) {
    // Navigation privee, stockage refuse par le navigateur: l'ecran de
    // demarrage gardera ses libelles d'origine. Rien de ce que fait
    // l'application n'en depend.
  }
}

void masquerEcranDeDemarrage() {
  try {
    _masquerLeDemarrage?.callAsFunction();
  } catch (_) {
    // Le sondage de `index.html` reste le filet: il retire le bloc de toute
    // facon des qu'il voit Flutter monte.
  }
}
