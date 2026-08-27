import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/availability.dart';

/// La collecte des disponibilites, avant que le planning existe.
///
/// L'ecran parlait a `dio` directement en manipulant des `Map` sans forme,
/// et lisait une grille qui decrivait une reservation exclusive. Les deux
/// ont change: le transport est ici, et la grille compte des declarants au
/// lieu de designer un proprietaire.
class AvailabilityRepository {
  final Dio dio;

  AvailabilityRepository(this.dio);

  List<Map<String, dynamic>> _lignes(dynamic data) {
    final List<dynamic> brutes;
    if (data is Map<String, dynamic> && data['results'] is List) {
      brutes = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      brutes = data;
    } else {
      brutes = const [];
    }
    return brutes
        .whereType<Map>()
        .map((ligne) => Map<String, dynamic>.from(ligne))
        .toList(growable: false);
  }

  Future<AvailabilityGrid> fetchGrid({
    int? teacherId,
    int startHour = 7,
    int endHour = 18,
    int slotMinutes = 60,
  }) async {
    final reponse = await dio.get(
      '/teacher-availability-slots/grid/',
      queryParameters: {
        'start_hour': startHour,
        'end_hour': endHour,
        'slot_minutes': slotMinutes,
        'teacher': ?teacherId,
      },
    );
    return AvailabilityGrid.fromJson(
      Map<String, dynamic>.from(reponse.data as Map),
    );
  }

  /// Declare un creneau. `teacherId` est facultatif: un enseignant qui
  /// declare pour lui-meme n'a pas a connaitre son propre identifiant.
  Future<void> declarer({
    required String dayOfWeek,
    required String startTime,
    required String endTime,
    required AvailabilityKind kind,
    int? teacherId,
    String note = '',
  }) async {
    await dio.post(
      '/teacher-availability-slots/',
      data: {
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
        'kind': kind.code,
        'note': note,
        'teacher': ?teacherId,
      },
    );
  }

  Future<void> changerLEtat(int slotId, AvailabilityKind kind) async {
    await dio.patch(
      '/teacher-availability-slots/$slotId/',
      data: {'kind': kind.code},
    );
  }

  Future<void> retirer(int slotId) async {
    await dio.delete('/teacher-availability-slots/$slotId/');
  }

  /// La campagne en cours pour l'etablissement actif, ou null.
  ///
  /// La liste arrive triee par ouverture decroissante: la premiere ouverte
  /// est celle qui court, et a defaut la plus recente sert d'historique.
  Future<AvailabilityCampaign?> fetchCampagneCourante() async {
    final reponse = await dio.get('/availability-campaigns/');
    final campagnes = _lignes(reponse.data).map(AvailabilityCampaign.fromJson);
    if (campagnes.isEmpty) return null;
    for (final campagne in campagnes) {
      if (campagne.isOpen) return campagne;
    }
    return campagnes.first;
  }

  Future<List<AvailabilityResponseRow>> fetchReponses(int campaignId) async {
    final reponse = await dio.get(
      '/availability-campaigns/$campaignId/responses/',
    );
    return _lignes(reponse.data)
        .map(AvailabilityResponseRow.fromJson)
        .toList(growable: false);
  }

  Future<int> relancer(int campaignId) async {
    final reponse = await dio.post(
      '/availability-campaigns/$campaignId/remind/',
      data: const {},
    );
    final data = Map<String, dynamic>.from(reponse.data as Map);
    return (data['reminded'] as num?)?.toInt() ?? 0;
  }

  /// « J'ai terminé »: ce geste separe le silence de l'indisponibilite.
  Future<void> rendre(int campaignId) async {
    await dio.post(
      '/availability-campaigns/$campaignId/submit/',
      data: const {},
    );
  }
}

final availabilityRepositoryProvider = Provider<AvailabilityRepository>((ref) {
  return AvailabilityRepository(ref.read(dioProvider));
});
