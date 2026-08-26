import 'package:dio/dio.dart';

import '../domain/discipline_incident.dart';

/// Acces reseau du module discipline.
///
/// La page interrogeait l'API directement, avec sa propre extraction de
/// `results` et ses propres filtres de perimetre. Tout passe desormais par
/// ici, et la pagination n'y figure pas: `followRemainingPages` la recolle
/// au niveau du client HTTP pour toute requete qui ne pilote pas ses pages
/// elle-meme. Envoyer `page_size` desactiverait ce recollement.
class DisciplineRepository {
  final Dio dio;

  DisciplineRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return const [];
  }

  /// Lit une collection entiere.
  ///
  /// Sans `page_size`: le client HTTP suit alors les liens `next` et rend
  /// la liste complete. Le lui repasser ici rendrait la main a l'appelant
  /// et tronquerait la reponse a une seule page.
  Future<List<Map<String, dynamic>>> _fetchAll(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await dio.get(path, queryParameters: query);
    return _extractRows(response.data)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /// Incidents visibles par le profil connecte.
  ///
  /// Aucun filtrage de perimetre ici: `get_queryset` restreint deja aux
  /// enfants du parent, aux classes de l'enseignant ou a l'etablissement.
  /// Le refaire cote client sur une page partielle ne protegeait rien et
  /// cachait des lignes legitimes.
  Future<List<DisciplineIncident>> fetchIncidents({
    String search = '',
    String status = '',
    String severity = '',
  }) async {
    final rows = await _fetchAll(
      '/discipline-incidents/',
      query: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (status.isNotEmpty) 'status': status,
        if (severity.isNotEmpty) 'severity': severity,
      },
    );
    return rows.map(DisciplineIncident.fromJson).toList(growable: false);
  }

  /// Eleves selectionnables pour une declaration.
  ///
  /// `/students/` ne restreint pas l'enseignant a ses classes -- d'autres
  /// ecrans en dependent -- alors que la creation d'incident, elle, la
  /// refuse. On demande donc les classes affectees, puis les eleves classe
  /// par classe: le serveur filtre, et la liste proposee correspond a ce
  /// qu'il acceptera.
  Future<List<DisciplineStudentOption>> fetchSelectableStudents({
    required bool asTeacher,
    int? currentUserId,
  }) async {
    if (!asTeacher || currentUserId == null) {
      return _toStudents(await _fetchAll('/students/'));
    }

    final teachers = await _fetchAll(
      '/teachers/',
      query: {'user': currentUserId},
    );
    if (teachers.isEmpty) return const [];
    final teacherId = (teachers.first['id'] as num?)?.toInt() ?? 0;
    if (teacherId <= 0) return const [];

    final assignments = await _fetchAll(
      '/teacher-assignments/',
      query: {'teacher': teacherId},
    );
    final classroomIds = assignments
        .map((row) => (row['classroom'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .toSet();
    if (classroomIds.isEmpty) return const [];

    final parClasse = await Future.wait(
      classroomIds.map(
        (id) => _fetchAll('/students/', query: {'classroom': id}),
      ),
    );

    // Un eleve ne peut relever que d'une classe, mais deux affectations sur
    // la meme classe le rameneraient deux fois.
    final vus = <int>{};
    final uniques = <Map<String, dynamic>>[];
    for (final row in parClasse.expand((rows) => rows)) {
      final id = (row['id'] as num?)?.toInt() ?? 0;
      if (id > 0 && vus.add(id)) uniques.add(row);
    }
    return _toStudents(uniques);
  }

  List<DisciplineStudentOption> _toStudents(List<Map<String, dynamic>> rows) {
    final options = rows
        .map(DisciplineStudentOption.fromJson)
        .where((option) => option.id > 0)
        .toList();
    options.sort((a, b) => a.libelle.toLowerCase().compareTo(
          b.libelle.toLowerCase(),
        ));
    return List.unmodifiable(options);
  }

  /// Referentiel des motifs, servi par le serveur.
  ///
  /// Le champ etait un texte libre pre-rempli « Indiscipline »: chaque
  /// etablissement inventait ses libelles et aucun comptage par motif
  /// n'etait exploitable. Recopier la liste ici l'aurait fait diverger du
  /// modele des la premiere evolution.
  Future<List<DisciplineCategoryOption>> fetchCategories() async {
    final response = await dio.get('/discipline-incidents/categories/');
    final data = response.data;
    final rows = data is List<dynamic> ? data : _extractRows(data);
    return rows
        .whereType<Map>()
        .map((row) => DisciplineCategoryOption.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .where((option) => option.value.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> createIncident({
    required int studentId,
    required String incidentDate,
    required String category,
    required String description,
    required String severity,
    String sanction = '',
    String status = 'open',
    bool parentNotified = false,
  }) async {
    await dio.post(
      '/discipline-incidents/',
      data: {
        'student': studentId,
        'incident_date': incidentDate,
        'category': category,
        'description': description,
        'severity': severity,
        'sanction': sanction,
        'status': status,
        'parent_notified': parentNotified,
      },
    );
  }

  /// Traitement d'un incident: sanction, cloture, information des parents.
  ///
  /// En PATCH et non en PUT: l'enseignant reste l'auteur de la declaration,
  /// et un arbitrage ne reecrit ni le motif ni la date.
  Future<void> updateIncident({
    required int id,
    String? sanction,
    String? status,
    bool? parentNotified,
    String? severity,
  }) async {
    await dio.patch(
      '/discipline-incidents/$id/',
      data: {
        'sanction': ?sanction,
        'status': ?status,
        'parent_notified': ?parentNotified,
        'severity': ?severity,
      },
    );
  }

  Future<void> deleteIncident(int id) async {
    await dio.delete('/discipline-incidents/$id/');
  }
}
