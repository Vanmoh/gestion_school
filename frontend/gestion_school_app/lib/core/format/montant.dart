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

/// « 5,0 M » — pour un axe de graphique, où le chiffre exact gênerait.
///
/// Les montants d'une école se comptent en millions: un axe qui écrit
/// « 6 750 000 FCFA » sur chaque graduation ne laisse plus de place aux
/// barres. La valeur exacte reste lisible ailleurs — l'infobulle de la barre
/// et le tableau sous le graphique la donnent en entier.
String montantAbrege(num valeur) {
  final absolu = valeur.abs();
  final signe = valeur < 0 ? '-' : '';
  if (absolu >= 1000000) {
    final millions = absolu / 1000000;
    final texte = millions >= 10
        ? millions.round().toString()
        : millions.toStringAsFixed(1).replaceAll('.', ',');
    return '$signe$texte M';
  }
  if (absolu >= 1000) {
    return '$signe${(absolu / 1000).round()} k';
  }
  return '$signe${absolu.round()}';
}
