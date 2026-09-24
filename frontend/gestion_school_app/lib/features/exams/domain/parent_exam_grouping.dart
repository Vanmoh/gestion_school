// Regroupement des résultats d'examen par enfant, pour la vue famille.
// Logique pure, isolée de la présentation pour rester testable.

import 'exam_models.dart';

/// Les résultats d'un même enfant, du plus récent au plus ancien.
class GroupeDExamensParEnfant {
  final int studentId;
  final String nomDeLEnfant;
  final String matricule;
  final List<ExamResultItem> resultats;

  const GroupeDExamensParEnfant({
    required this.studentId,
    required this.nomDeLEnfant,
    required this.matricule,
    required this.resultats,
  });

  /// La moyenne des notes publiées de cet enfant, ou `null` s'il n'en a
  /// aucune.
  ///
  /// Calculée sur ce qui est affiché, et rien d'autre : le serveur ne
  /// transmet que les notes publiées, et présenter une moyenne qui en
  /// contiendrait d'autres serait annoncer un chiffre que la famille ne peut
  /// pas retrouver ligne à ligne.
  double? get moyenne {
    if (resultats.isEmpty) return null;
    final total = resultats.fold<double>(0, (somme, r) => somme + r.score);
    return total / resultats.length;
  }
}

/// Groupe les résultats par enfant, chaque groupe trié de la note la plus
/// récente à la plus ancienne, les groupes eux-mêmes triés par nom.
///
/// Prend des résultats typés et non des `Map` brutes : la vue famille de
/// discipline lisait directement le JSON de l'API, si bien qu'un champ
/// renommé côté serveur ne se voyait qu'à l'exécution, sur un écran vide.
List<GroupeDExamensParEnfant> grouperLesExamensParEnfant(
  List<ExamResultItem> resultats,
) {
  final paniers = <int, List<ExamResultItem>>{};
  final noms = <int, String>{};
  final matricules = <int, String>{};

  for (final resultat in resultats) {
    final cle = resultat.studentId;
    paniers.putIfAbsent(cle, () => <ExamResultItem>[]).add(resultat);

    // Le nom peut manquer sur certaines lignes : on garde le premier non
    // vide plutôt que d'écraser un libellé par un vide.
    final nom = resultat.studentFullName.trim();
    if (nom.isNotEmpty) {
      noms.putIfAbsent(cle, () => nom);
    }
    final matricule = resultat.studentMatricule.trim();
    if (matricule.isNotEmpty) {
      matricules.putIfAbsent(cle, () => matricule);
    }
  }

  final groupes = paniers.entries.map((entree) {
    // Par identifiant décroissant : le serveur n'envoie pas de date de
    // saisie sur un résultat, et l'identifiant suit l'ordre de création.
    final tries = [...entree.value]..sort((a, b) => b.id.compareTo(a.id));
    return GroupeDExamensParEnfant(
      studentId: entree.key,
      nomDeLEnfant: noms[entree.key] ?? 'Élève',
      matricule: matricules[entree.key] ?? '',
      resultats: tries,
    );
  }).toList();

  groupes.sort((a, b) => a.nomDeLEnfant.compareTo(b.nomDeLEnfant));
  return groupes;
}

/// Les épreuves encore à venir, de la plus proche à la plus lointaine.
///
/// `aujourdHui` est passé plutôt que lu : un test qui dépend de l'horloge
/// tombe le jour où l'épreuve du décor devient passée.
List<ExamPlanningItem> epreuvesAVenir(
  List<ExamPlanningItem> plannings,
  DateTime aujourdHui,
) {
  final jour = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
  final futures = plannings.where((planning) {
    final date = DateTime.tryParse(planning.examDate);
    // Une date illisible n'est pas une date passée : on la garde plutôt que
    // de faire disparaître une épreuve d'un calendrier.
    if (date == null) return true;
    return !date.isBefore(jour);
  }).toList();

  futures.sort((a, b) {
    final da = DateTime.tryParse(a.examDate);
    final db = DateTime.tryParse(b.examDate);
    if (da == null || db == null) return a.examDate.compareTo(b.examDate);
    final parJour = da.compareTo(db);
    return parJour != 0 ? parJour : a.startTime.compareTo(b.startTime);
  });
  return futures;
}
