import 'package:dio/dio.dart';

import '../../../core/network/chargement_tolerant.dart';
import '../domain/reports_models.dart';

/// Les documents que l'école délivre, et le référentiel qui les désigne.
///
/// L'écran appelait Dio depuis son `State` et, faute de pagination, recevait
/// tous les encaissements de l'école pour en afficher dix. Le serveur les
/// découpe désormais (`/reports/receipts/`), et la recherche part avec.
class ReportsRepository {
  final Dio dio;

  ReportsRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return [];
  }

  double _versDouble(dynamic valeur) {
    if (valeur is num) return valeur.toDouble();
    return double.tryParse(valeur?.toString() ?? '') ?? 0;
  }

  Future<ContexteDesRapports> fetchContexte() async {
    // Le contexte tombe en 404 sur les déploiements qui n'ont pas encore la
    // vue: on se rabat alors sur les deux référentiels qu'elle regroupe.
    late final Response<dynamic> reponse;
    try {
      reponse = await dio.get('/reports/context/');
    } on DioException catch (erreur) {
      if (erreur.response?.statusCode != 404) rethrow;
      return _contexteEnDeuxRequetes();
    }

    final donnees = reponse.data;
    if (donnees is! Map<String, dynamic>) return ContexteDesRapports.vide;

    return ContexteDesRapports(
      eleves: _elevesDe(donnees['students']),
      annees: _anneesDe(donnees['academic_years']),
      nombreDEncaissements: (donnees['payments_count'] as num?)?.toInt() ?? 0,
      totalEncaisse: _versDouble(donnees['payments_total']),
    );
  }

  Future<ContexteDesRapports> _contexteEnDeuxRequetes() async {
    final reponses = await Future.wait([
      dio.get('/students/'),
      reponseTolerante(dio.get('/academic-years/')),
    ]);

    return ContexteDesRapports(
      eleves: _elevesDe(reponses[0].data),
      annees: _anneesDe(reponses[1].data),
      nombreDEncaissements: 0,
      totalEncaisse: 0,
    );
  }

  List<OptionEleve> _elevesDe(dynamic donnees) {
    return _extractRows(donnees)
        .map((row) => (row as Map<String, dynamic>))
        .map((row) {
          final compte = row['user'];
          final nomComplet = row['student_full_name']?.toString() ??
              (compte is Map<String, dynamic>
                  ? [
                      compte['first_name']?.toString() ?? '',
                      compte['last_name']?.toString() ?? '',
                    ].where((part) => part.trim().isNotEmpty).join(' ').trim()
                  : '');
          final classe = row['classroom_name']?.toString() ?? '';
          return OptionEleve(
            id: (row['id'] as num?)?.toInt() ?? 0,
            nom: nomComplet.isEmpty
                ? (row['matricule']?.toString() ?? 'Élève')
                : nomComplet,
            matricule: row['matricule']?.toString() ?? '',
            classe: classe,
            classeId: (row['classroom'] as num?)?.toInt(),
          );
        })
        .toList(growable: false);
  }

  List<OptionAnnee> _anneesDe(dynamic donnees) {
    return _extractRows(donnees)
        .map((row) => (row as Map<String, dynamic>))
        .map(
          (row) => OptionAnnee(
            id: (row['id'] as num?)?.toInt() ?? 0,
            nom: row['name']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<PageDeRecus> fetchRecus({String recherche = '', int page = 1}) async {
    final reponse = await dio.get(
      '/reports/receipts/',
      queryParameters: {
        if (recherche.trim().isNotEmpty) 'search': recherche.trim(),
        'page': page,
        // La vue pagine par vingt: on l'annonce pour que l'intercepteur du
        // projet ne demande pas cinq cents lignes à sa place.
        'page_size': 20,
      },
    );

    final donnees = reponse.data;
    if (donnees is! Map<String, dynamic>) return PageDeRecus.vide;

    return PageDeRecus(
      total: (donnees['count'] as num?)?.toInt() ?? 0,
      page: (donnees['page'] as num?)?.toInt() ?? page,
      pages: (donnees['pages'] as num?)?.toInt() ?? 1,
      lignes: _extractRows(donnees)
          .map((row) => (row as Map<String, dynamic>))
          .map(
            (row) => RecuItem(
              id: (row['id'] as num?)?.toInt() ?? 0,
              quand: row['created_at']?.toString() ?? '',
              eleve: row['student_full_name']?.toString() ?? '',
              matricule: row['student_matricule']?.toString() ?? '',
              typeDeFrais: row['fee_type']?.toString() ?? '',
              montant: _versDouble(row['amount']),
              moyen: row['method']?.toString() ?? '',
              reference: row['reference']?.toString() ?? '',
              encaissePar: row['received_by']?.toString() ?? '',
            ),
          )
          .toList(growable: false),
    );
  }

  Future<List<int>> recuEnPdf(int paiementId) async {
    final reponse = await dio.get<List<int>>(
      '/reports/receipt/$paiementId/',
      options: Options(responseType: ResponseType.bytes),
    );
    return reponse.data ?? const [];
  }

  Future<List<int>> exportDesPaiementsEnExcel() async {
    final reponse = await dio.get<List<int>>(
      '/reports/payments/export-excel/',
      options: Options(responseType: ResponseType.bytes),
    );
    return reponse.data ?? const [];
  }

  /// Le journal de caisse, que rien dans l'application n'atteignait.
  ///
  /// Le serveur le sert depuis toujours — page et export — et seul celui des
  /// dépenses avait trouvé un écran.
  Future<List<int>> journalDeCaisseEnExcel() async {
    final reponse = await dio.get<List<int>>(
      '/reports/journal-payments/export/',
      options: Options(responseType: ResponseType.bytes),
    );
    return reponse.data ?? const [];
  }

  Future<List<int>> journalDesDepensesEnExcel() async {
    final reponse = await dio.get<List<int>>(
      '/reports/journal-expenses/export/',
      options: Options(responseType: ResponseType.bytes),
    );
    return reponse.data ?? const [];
  }

  Future<List<int>> listeDuPersonnelEnPdf() async {
    final reponse = await dio.get<List<int>>(
      '/reports/staff-roster/',
      options: Options(responseType: ResponseType.bytes),
    );
    return reponse.data ?? const [];
  }

  Future<List<int>> listesDeClasseEnPdf() async {
    final reponse = await dio.get<List<int>>(
      '/reports/class-roster/',
      options: Options(responseType: ResponseType.bytes),
    );
    return reponse.data ?? const [];
  }
}
