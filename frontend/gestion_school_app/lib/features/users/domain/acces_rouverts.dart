/// Les accès rendus à une classe, tels que le serveur les compose.
///
/// Le mot de passe n'existe en clair qu'à cet instant : le serveur le hache
/// dès qu'il le pose, et il ne repassera jamais. C'est pourquoi cet objet
/// existe — sans lui, la réouverture aurait changé des mots de passe que
/// personne n'aurait pu dicter.
class AccesRouverts {
  final List<AccesDUneFamille> comptes;

  /// Les comptes laissés tels quels parce qu'ils servent déjà.
  ///
  /// Sans ce nombre, une liste plus courte que la classe passerait pour un
  /// oubli, et on recommencerait.
  final int dejaUtilises;

  const AccesRouverts({this.comptes = const [], this.dejaUtilises = 0});

  factory AccesRouverts.fromJson(dynamic data) {
    if (data is! Map) return const AccesRouverts();
    final lignes = data['comptes'];
    return AccesRouverts(
      comptes: lignes is List
          ? lignes
                .whereType<Map>()
                .map(AccesDUneFamille.fromJson)
                .toList(growable: false)
          : const [],
      dejaUtilises: (data['deja_utilises'] as num?)?.toInt() ?? 0,
    );
  }

  bool get estVide => comptes.isEmpty;
}

/// Une ligne : l'élève, et son parent quand lui non plus n'était jamais entré.
class AccesDUneFamille {
  final String eleve;
  final String matricule;
  final String classe;
  final String identifiant;
  final String motDePasse;
  final String parent;
  final String parentIdentifiant;
  final String parentMotDePasse;

  const AccesDUneFamille({
    this.eleve = '',
    this.matricule = '',
    this.classe = '',
    this.identifiant = '',
    this.motDePasse = '',
    this.parent = '',
    this.parentIdentifiant = '',
    this.parentMotDePasse = '',
  });

  factory AccesDUneFamille.fromJson(Map<dynamic, dynamic> json) {
    String texte(String cle) => (json[cle] ?? '').toString().trim();
    return AccesDUneFamille(
      eleve: texte('eleve'),
      matricule: texte('matricule'),
      classe: texte('classe'),
      identifiant: texte('identifiant'),
      motDePasse: texte('mot_de_passe'),
      parent: texte('parent'),
      parentIdentifiant: texte('parent_identifiant'),
      parentMotDePasse: texte('parent_mot_de_passe'),
    );
  }

  /// Vrai quand l'élève lui-même entrait déjà : seul son parent a été rouvert.
  bool get seulLeParent => motDePasse.isEmpty && parentMotDePasse.isNotEmpty;

  bool get porteUnParent => parentMotDePasse.isNotEmpty;
}
