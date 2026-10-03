/// Comment un enseignant obtient sa fiche et ses affectations.
///
/// Le module « teachers » lui est fermé — c'est de la gestion du personnel, et
/// son écran n'a rien à faire dans sa barre latérale. `/teachers/` et
/// `/teacher-assignments/` lui répondent donc **403**.
///
/// Or cinq écrans les réclamaient pour savoir quelles classes lui montrer :
/// tableau de bord, notes, discipline, emploi du temps, disponibilités. La
/// couche réseau avalait les refus, et chacun concluait à sa façon qu'il
/// n'enseignait nulle part. Une enseignante affectée à deux matières voyait
/// « Classes 0 » et un sélecteur vide, sans qu'un seul message n'explique
/// pourquoi.
///
/// Deux routes réservées au compte connecté règlent le cas sans ouvrir
/// l'annuaire : `teachers/mon-profil` (qui existait déjà, posée pour l'écran
/// d'émargement) et `teacher-assignments/mes-affectations`. Ce module dit
/// laquelle appeler, pour que le choix vive à un seul endroit plutôt que
/// recopié dans chaque écran — c'est la recopie qui a fait que la correction de
/// l'émargement n'a pas profité aux autres.
library;

/// Le rôle qui n'a pas accès à l'annuaire du personnel.
bool estEnseignant(String? role) => role == 'teacher';

/// Où lire la fiche enseignant : la sienne, ou l'annuaire.
String routeDeLaFicheEnseignant(String? role) =>
    estEnseignant(role) ? '/teachers/mon-profil/' : '/teachers/';

/// Où lire les affectations : les siennes, ou toutes.
String routeDesAffectations(String? role) => estEnseignant(role)
    ? '/teacher-assignments/mes-affectations/'
    : '/teacher-assignments/';

/// Ramène la réponse à une liste de lignes.
///
/// `mon-profil` rend **un objet**, `/teachers/` une liste paginée : sans cette
/// conversion, chaque appelant devrait connaître la différence, et c'est
/// précisément le genre de détail qu'on oublie dans un écran sur cinq.
List<Map<String, dynamic>> lignesDeLaFiche(dynamic donnees) {
  if (donnees is Map<String, dynamic>) {
    // Une réponse paginée est aussi un `Map`: on la distingue par `results`.
    final resultats = donnees['results'];
    if (resultats is List) {
      return resultats
          .whereType<Map>()
          .map((ligne) => Map<String, dynamic>.from(ligne))
          .toList(growable: false);
    }
    return donnees.isEmpty ? const [] : [donnees];
  }
  if (donnees is List) {
    return donnees
        .whereType<Map>()
        .map((ligne) => Map<String, dynamic>.from(ligne))
        .toList(growable: false);
  }
  return const [];
}
