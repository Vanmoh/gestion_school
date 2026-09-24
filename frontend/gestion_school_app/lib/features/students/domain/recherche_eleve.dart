// Ce qui, dans une recherche d'eleve, designe quelqu'un plutot que de le
// decrire. Logique pure, isolee de la presentation pour rester testable.

import 'student.dart';

/// L'eleve que cette recherche nomme sans ambiguite, ou `null`.
///
/// Le serveur cherche par fragment, et c'est ce qu'il faut tant qu'on
/// tatonne: « diallo » doit ramener les deux Diallo. Mais un matricule
/// entier, un numero entier, un identifiant entier ne tatonnent pas -- ils
/// nomment une personne, et la fenetre des correspondances n'a plus rien a
/// demander. Le fragment, lui, continue de ramener sa liste.
///
/// `null` des qu'il y a un doute: zero correspondance exacte, ou plusieurs
/// (deux enfants derriere le numero d'un meme parent). Choisir au hasard
/// dans ce cas serait exactement le defaut qu'on corrige.
Student? eleveDesigneExactement(List<Student> eleves, String recherche) {
  final cherche = _normaliser(recherche);
  if (cherche.isEmpty) return null;

  Student? trouve;
  for (final eleve in eleves) {
    if (!_designations(eleve).contains(cherche)) continue;
    // Deux exacts: la recherche decrit, elle ne designe pas.
    if (trouve != null) return null;
    trouve = eleve;
  }
  return trouve;
}

/// Les ecritures d'un eleve qui valent designation.
///
/// La classe et le nom du parent n'y sont pas: ils designent un groupe, et
/// un groupe se choisit dans une liste.
Set<String> _designations(Student eleve) {
  return {
    _normaliser(eleve.matricule),
    _normaliser(eleve.username),
    _normaliser(eleve.phone),
    _normaliser(eleve.parentPhone),
    _normaliser(eleve.fullName),
    // « BAGAYOKO Ousmane » autant que « Ousmane BAGAYOKO »: l'ecole ecrit
    // le nom en premier sur ses listes, et c'est de la qu'on recopie.
    _normaliser('${eleve.lastName} ${eleve.firstName}'),
  }..remove('');
}

/// Meme texte a l'oeil, meme texte ici: casse, espaces, points et tirets ne
/// distinguent pas deux ecritures d'un matricule ou d'un numero.
String _normaliser(String valeur) {
  final buffer = StringBuffer();
  for (final unite in valeur.toLowerCase().trim().runes) {
    final caractere = String.fromCharCode(unite);
    if (caractere == ' ' ||
        caractere == '.' ||
        caractere == '-' ||
        caractere == '_' ||
        caractere == '/') {
      continue;
    }
    buffer.write(caractere);
  }
  return buffer.toString();
}
