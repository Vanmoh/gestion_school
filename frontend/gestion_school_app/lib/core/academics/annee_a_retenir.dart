/// Quelle année scolaire un écran doit présenter par défaut.
///
/// Cinq écrans — notes, bulletins, cantine, promotion, élèves — retenaient
/// `annees.first`, c'est-à-dire la première ligne servie par l'API. Or aucun
/// ordre n'était défini, ni sur `AcademicYear`, ni sur sa vue: la « première »
/// dépendait de l'ordre physique des lignes en base, qui change dès qu'on en
/// met une à jour.
///
/// Le jour où ce hasard a désigné l'année suivante, l'écran « Notes &
/// Bulletins » a affiché « Aucune note enregistrée » sur une base qui en
/// comptait soixante-huit mille, et les bulletins imprimés portaient des tirets
/// partout. Rien n'était cassé: on interrogeait simplement une autre année que
/// celle qu'affichait l'en-tête.
///
/// La règle est celle que `AnneeScolaireController` applique déjà pour le
/// sélecteur global: **l'année active de l'établissement, à défaut la plus
/// récente**. Elle est ici pour les écrans qui manipulent des `Map` brutes
/// venues de l'API, et qui ne passent pas par le contrôleur typé.
library;

/// L'identifiant de l'année à retenir, ou `null` si la liste est vide.
///
/// [annees] est une liste de lignes telles que l'API les rend, avec au moins
/// `id`, et si possible `is_active` et `start_date`.
int? anneeARetenir(List<Map<String, dynamic>> annees) {
  final ligne = ligneDeLAnneeARetenir(annees);
  if (ligne == null) return null;
  final id = _entier(ligne['id']);
  return id > 0 ? id : null;
}

/// La ligne complète, quand l'appelant a besoin du nom ou des dates.
Map<String, dynamic>? ligneDeLAnneeARetenir(List<Map<String, dynamic>> annees) {
  if (annees.isEmpty) return null;

  for (final annee in annees) {
    if (annee['is_active'] == true) return annee;
  }

  // Aucune année active: la plus récente par date de début. On ne se rabat sur
  // `first` qu'en dernier recours, et seulement parce qu'il faut bien montrer
  // quelque chose -- jamais comme règle.
  //
  // Une boucle plutôt que `reduce`: celui-ci exige que la fonction de
  // combinaison ait exactement le type de la liste, et l'appelant passe souvent
  // un `List<Map<String, Object>>` déduit d'un littéral. `reduce` levait alors
  // « is not a subtype of ... of combine » — au moment précis où il n'y a pas
  // d'année active, c'est-à-dire là où personne ne regarde.
  Map<String, dynamic>? retenue;
  DateTime? debutRetenu;
  for (final annee in annees) {
    final debut = _dateDeDebut(annee);
    if (debut == null) continue;
    if (debutRetenu == null || debut.isAfter(debutRetenu)) {
      retenue = annee;
      debutRetenu = debut;
    }
  }

  return retenue ?? annees.first;
}

DateTime? _dateDeDebut(Map<String, dynamic> annee) {
  final brut = annee['start_date'];
  if (brut is DateTime) return brut;
  if (brut is String && brut.isNotEmpty) return DateTime.tryParse(brut);
  return null;
}

int _entier(dynamic valeur) {
  if (valeur is int) return valeur;
  if (valeur is num) return valeur.toInt();
  return int.tryParse('${valeur ?? ''}') ?? 0;
}
