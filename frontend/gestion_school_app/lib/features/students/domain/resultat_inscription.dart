import 'student.dart';

/// Ce qu'on remet à la famille au moment de l'inscription.
///
/// Le mot de passe n'existe en clair qu'ici, dans cette réponse: le serveur
/// le hache dès qu'il le pose. Il ne repassera jamais — s'il n'est pas noté
/// maintenant, il faudra le réinitialiser.
class IdentifiantsRemis {
  final String username;
  final String motDePasse;

  const IdentifiantsRemis({required this.username, required this.motDePasse});

  factory IdentifiantsRemis.fromJson(Map<String, dynamic> json) {
    return IdentifiantsRemis(
      username: (json['username'] ?? '').toString(),
      motDePasse: (json['mot_de_passe'] ?? '').toString(),
    );
  }
}

class ResultatInscription {
  final Student eleve;
  final IdentifiantsRemis identifiantsEleve;

  /// Nom du parent, créé ou retrouvé.
  final String parentNom;
  final int parentId;

  /// Faux quand l'élève a rejoint un parent déjà enregistré: celui-ci garde
  /// alors le mot de passe qu'il a déjà, et rien de nouveau n'est à remettre.
  final bool parentCree;
  final IdentifiantsRemis? identifiantsParent;

  const ResultatInscription({
    required this.eleve,
    required this.identifiantsEleve,
    required this.parentNom,
    required this.parentId,
    required this.parentCree,
    this.identifiantsParent,
  });

  factory ResultatInscription.fromJson(Map<String, dynamic> json) {
    final parent = Map<String, dynamic>.from(
      (json['parent'] as Map?) ?? const {},
    );
    final identifiantsParent = json['identifiants_parent'];

    return ResultatInscription(
      eleve: Student.fromJson(Map<String, dynamic>.from(json['eleve'] as Map)),
      identifiantsEleve: IdentifiantsRemis.fromJson(
        Map<String, dynamic>.from(json['identifiants_eleve'] as Map),
      ),
      parentNom: (parent['nom'] ?? '').toString(),
      parentId: (parent['id'] as num?)?.toInt() ?? 0,
      parentCree: parent['cree'] == true,
      identifiantsParent: identifiantsParent is Map
          ? IdentifiantsRemis.fromJson(
              Map<String, dynamic>.from(identifiantsParent),
            )
          : null,
    );
  }
}
