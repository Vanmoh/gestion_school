import 'package:dio/dio.dart';

import '../domain/annee_scolaire.dart';

/// Acces aux annees scolaires de l'etablissement actif.
///
/// La pagination n'y figure pas: `followRemainingPages` la recolle au
/// niveau du client HTTP pour toute requete qui ne pilote pas ses pages
/// elle-meme. Envoyer `page_size` desactiverait ce recollement.
class AnneesScolairesRepository {
  final Dio dio;

  AnneesScolairesRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) return data;
    return const [];
  }

  Future<List<AnneeScolaire>> fetchAnnees() async {
    final response = await dio.get(
      '/academic-years/',
      queryParameters: const {'ordering': '-start_date'},
    );
    return _extractRows(response.data)
        .whereType<Map>()
        .map((row) => AnneeScolaire.fromJson(Map<String, dynamic>.from(row)))
        .where((annee) => annee.id > 0)
        .toList(growable: false);
  }

  Future<AnneeScolaire> creerAnnee({
    required String nom,
    required String debut,
    required String fin,
  }) async {
    final response = await dio.post(
      '/academic-years/',
      data: {'name': nom, 'start_date': debut, 'end_date': fin},
    );
    return AnneeScolaire.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  /// Ouvre une annee en reprenant la structure de la precedente.
  ///
  /// Rend le compte-rendu de ce qui a ete repris: c'est ce que l'ecran
  /// affiche ensuite, plutot qu'un « operation reussie » qui ne dirait pas
  /// si les quinze classes attendues sont bien la.
  Future<Map<String, dynamic>> ouvrirAnnee({
    required String nom,
    required String debut,
    required String fin,
    int? sourceId,
    bool dupliquerClasses = true,
    bool dupliquerMatieres = true,
    bool dupliquerAffectations = true,
    bool dupliquerEmploiDuTemps = true,
    bool activer = false,
    bool cloturerSource = false,
  }) async {
    final response = await dio.post(
      '/academic-years/ouvrir/',
      data: {
        'name': nom,
        'start_date': debut,
        'end_date': fin,
        'source_academic_year': ?sourceId,
        'dupliquer_classes': dupliquerClasses,
        'dupliquer_matieres': dupliquerMatieres,
        'dupliquer_affectations': dupliquerAffectations,
        'dupliquer_emploi_du_temps': dupliquerEmploiDuTemps,
        'activer': activer,
        'cloturer_source': cloturerSource,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Designe l'annee de saisie. Le serveur retire la precedente dans le
  /// meme mouvement: une seule peut etre ouverte par etablissement.
  Future<AnneeScolaire> activer(int id) => _action(id, 'activer');

  Future<AnneeScolaire> cloturer(int id) => _action(id, 'cloturer');

  Future<AnneeScolaire> rouvrir(int id) => _action(id, 'rouvrir');

  Future<AnneeScolaire> _action(int id, String action) async {
    final response = await dio.post('/academic-years/$id/$action/');
    return AnneeScolaire.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }
}
