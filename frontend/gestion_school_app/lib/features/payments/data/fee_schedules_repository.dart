import 'package:dio/dio.dart';

import '../domain/fee_schedule.dart';

/// Accès aux barèmes de frais et à leur application en masse.
class FeeSchedulesRepository {
  final Dio dio;

  FeeSchedulesRepository(this.dio);

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    return const [];
  }

  FeeSchedule _mapper(Map<String, dynamic> map) {
    return FeeSchedule(
      id: _toInt(map['id']),
      academicYearId: _toInt(map['academic_year']),
      classroomId: map['classroom'] == null ? null : _toInt(map['classroom']),
      classroomName: map['classroom_name']?.toString() ?? '',
      feeType: map['fee_type']?.toString() ?? '',
      feeTypeDisplay: map['fee_type_display']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      amount: _toDouble(map['amount']),
      firstDueDate: map['first_due_date']?.toString() ?? '',
      occurrences: _toInt(map['occurrences']),
      echeances: _toStringList(map['echeances']),
      montantTotal: _toDouble(map['montant_total']),
      elevesConcernes: _toInt(map['eleves_concernes']),
      fraisGeneres: _toInt(map['frais_generes']),
    );
  }

  Future<List<FeeSchedule>> fetchSchedules({int? academicYearId}) async {
    final response = await dio.get(
      '/fee-schedules/',
      queryParameters: {
        'page_size': 200,
        'academic_year': ?academicYearId,
      },
    );

    final data = response.data;
    final rows = data is Map<String, dynamic> && data['results'] is List
        ? data['results'] as List<dynamic>
        : (data is List<dynamic> ? data : const <dynamic>[]);

    return rows
        .map((row) => _mapper(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<FeeSchedule> create({
    required int academicYearId,
    int? classroomId,
    required String feeType,
    required double amount,
    required String firstDueDate,
    required int occurrences,
    String label = '',
  }) async {
    final response = await dio.post(
      '/fee-schedules/',
      data: {
        'academic_year': academicYearId,
        // null et non absent: c'est ainsi que le serveur comprend « toutes
        // les classes de l'année ».
        'classroom': classroomId,
        'fee_type': feeType,
        'amount': amount,
        'first_due_date': firstDueDate,
        'occurrences': occurrences,
        'label': label,
      },
    );
    return _mapper(response.data as Map<String, dynamic>);
  }

  Future<void> delete(int id) async {
    await dio.delete('/fee-schedules/$id/');
  }

  /// Ce que l'application produirait, sans rien écrire.
  Future<FeeScheduleApercu> apercu(int id) async {
    final response = await dio.get('/fee-schedules/$id/apercu/');
    final map = response.data as Map<String, dynamic>;
    return FeeScheduleApercu(
      elevesConcernes: _toInt(map['eleves_concernes']),
      echeances: _toStringList(map['echeances']),
      montantParEcheance: _toDouble(map['montant_par_echeance']),
      montantParEleve: _toDouble(map['montant_par_eleve']),
      montantTotal: _toDouble(map['montant_total']),
      fraisDejaGeneres: _toInt(map['frais_deja_generes']),
      fraisACreer: _toInt(map['frais_a_creer']),
    );
  }

  /// Crée les frais manquants pour ce barème. Rejouable sans doublonner.
  Future<String> appliquer(int id) async {
    final response = await dio.post('/fee-schedules/$id/appliquer/');
    final map = response.data as Map<String, dynamic>;
    return map['detail']?.toString() ?? 'Frais générés.';
  }

  /// Applique tous les barèmes d'une année: le geste de la rentrée.
  Future<String> appliquerTout({int? academicYearId}) async {
    final response = await dio.post(
      '/fee-schedules/appliquer-tout/',
      data: {'academic_year': ?academicYearId},
    );
    final map = response.data as Map<String, dynamic>;
    return map['detail']?.toString() ?? 'Frais générés.';
  }
}
