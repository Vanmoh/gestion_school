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
