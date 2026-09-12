/// Écrire une somme d'argent, partout de la même façon.
///
/// La fonction vivait dans les communs du module Finances. Elle sert
/// maintenant aussi hors de lui — la fiche d'un élève annonce ce qu'il reste
/// à régler sur son inscription — et une école ne doit pas lire « 25000 F »
/// ici et « 25 000 FCFA » là.
library;

/// « 125 000 FCFA ». Les milliers séparés par une espace, comme on les écrit
/// ici, et la devise collée au nombre.
String montantEnFrancs(num valeur) {
  final entier = valeur.round();
  final chiffres = entier.abs().toString();
  final groupes = chiffres.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (correspondance) => '${correspondance[1]} ',
  );
  // Le signe se pose après le groupement: le glisser dans le compte des
  // chiffres décalerait les espaces d'un rang.
  final signe = entier < 0 ? '-' : '';
  return '$signe$groupes FCFA';
}
