/// Le nom d'un rôle tel qu'on le dit dans l'école.
///
/// La table vivait, privée, dans `users_page.dart`. Tout autre écran qui
/// devait nommer un rôle l'affichait en anglais technique — « accountant »,
/// « supervisor » — ou s'en recopiait une part. Une seule table, ici.
///
/// Les codes sont ceux de `UserRole` côté serveur, et les libellés ceux de sa
/// propre énumération: c'est ce que la direction lit sur ses écrans de
/// gestion des comptes.
const Map<String, String> libellesDesRoles = {
  'super_admin': 'Super Admin',
  'director': 'Directeur/Proviseur',
  'promoter': 'Promoteur',
  'censor': 'Censeur',
  'accountant': 'Comptable',
  'teacher': 'Enseignant',
  'supervisor': 'Surveillant',
  'parent': 'Parent',
  'student': 'Élève',
};

/// Le libellé d'un rôle, ou son code si le serveur en sert un nouveau.
///
/// On rend le code plutôt que rien: un rôle ajouté côté serveur et pas encore
/// nommé ici reste lisible, au lieu de laisser une case vide devant un nom de
/// personne.
String roleEnClair(String? code) {
  if (code == null || code.isEmpty) return '';
  return libellesDesRoles[code] ?? code;
}
