import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/timesheet_concordance.dart';

/// Le rapprochement planning / emargement, tel que le serveur le calcule.
///
/// Le calcul n'a rien a faire cote client: lui seul connait les creneaux
/// reellement couverts par chaque pointage, et deux ecrans qui le
/// referaient chacun a sa facon finiraient par annoncer deux chiffres
/// differents pour la meme semaine.
class TimesheetRepository {
  final Dio dio;

  TimesheetRepository(this.dio);

  Future<TimesheetConcordance> fetchConcordance({
    required DateTime from,
    required DateTime to,
    int? teacherId,
  }) async {
    final reponse = await dio.get(
      '/teacher-time-entries/concordance/',
      queryParameters: {
        'from': _jour(from),
        'to': _jour(to),
        'teacher': ?teacherId,
      },
    );
    return TimesheetConcordance.fromJson(
      Map<String, dynamic>.from(reponse.data as Map),
    );
  }

  String _jour(DateTime valeur) {
    final mois = valeur.month.toString().padLeft(2, '0');
    final jour = valeur.day.toString().padLeft(2, '0');
    return '${valeur.year.toString().padLeft(4, '0')}-$mois-$jour';
  }
}

final timesheetRepositoryProvider = Provider<TimesheetRepository>((ref) {
  return TimesheetRepository(ref.read(dioProvider));
});
