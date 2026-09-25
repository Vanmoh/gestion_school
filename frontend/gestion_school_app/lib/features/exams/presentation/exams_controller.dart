import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/exams_repository.dart';
import '../domain/exam_models.dart';

final examsRepositoryProvider = Provider<ExamsRepository>((ref) {
  return ExamsRepository(ref.read(dioProvider));
});

final examSessionsProvider = FutureProvider<List<ExamSessionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchSessions();
});

/// Ce sur quoi le calendrier se filtre, porté au serveur.
///
/// Une classe à part plutôt que trois paramètres: un `family` prend une seule
/// clé, et elle doit savoir se comparer — sans quoi chaque reconstruction
/// relancerait la requête.
class FiltreDesEpreuves {
  final int? sessionId;
  final int? classroomId;
  final bool? publiees;

  const FiltreDesEpreuves({this.sessionId, this.classroomId, this.publiees});

  /// Aucun filtre: tout le calendrier.
  static const aucun = FiltreDesEpreuves();

  bool get estVide =>
      sessionId == null && classroomId == null && publiees == null;

  FiltreDesEpreuves avec({
    int? sessionId,
    int? classroomId,
    bool? publiees,
    bool viderSession = false,
    bool viderClasse = false,
    bool viderPublication = false,
  }) {
    return FiltreDesEpreuves(
      sessionId: viderSession ? null : (sessionId ?? this.sessionId),
      classroomId: viderClasse ? null : (classroomId ?? this.classroomId),
      publiees: viderPublication ? null : (publiees ?? this.publiees),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FiltreDesEpreuves &&
      other.sessionId == sessionId &&
      other.classroomId == classroomId &&
      other.publiees == publiees;

  @override
  int get hashCode => Object.hash(sessionId, classroomId, publiees);
}

final examPlanningsProvider =
    FutureProvider.family<List<ExamPlanningItem>, FiltreDesEpreuves>((
      ref,
      filtre,
    ) async {
      return ref.read(examsRepositoryProvider).fetchPlannings(
        sessionId: filtre.sessionId,
        classroomId: filtre.classroomId,
        publiees: filtre.publiees,
      );
    });

/// Les notes d'une épreuve, pour relire ce qu'on s'apprête à publier.
final notesDeLEpreuveProvider =
    FutureProvider.family<List<ExamResultItem>, int>((ref, planningId) async {
      return ref.read(examsRepositoryProvider).fetchResults(
        planningId: planningId,
      );
    });

final examResultsProvider = FutureProvider<List<ExamResultItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchResults();
});

final examInvigilationsProvider = FutureProvider<List<ExamInvigilationItem>>((
  ref,
) async {
  return ref.read(examsRepositoryProvider).fetchInvigilations();
});

final examAcademicYearsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchAcademicYears();
});

final examClassroomsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchClassrooms();
});

final examSubjectsProvider = FutureProvider.family<List<OptionItem>, int?>(
  (ref, classroomId) async {
    return ref.read(examsRepositoryProvider).fetchSubjects(
      classroomId: classroomId,
    );
  },
);

final examStudentsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchStudents();
});

final examSupervisorsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchSupervisors();
});

final examMutationProvider =
    StateNotifierProvider<ExamMutationController, AsyncValue<void>>((ref) {
      return ExamMutationController(ref);
    });

class ExamMutationController extends StateNotifier<AsyncValue<void>> {
  ExamMutationController(this.ref) : super(const AsyncValue.data(null));

  final Ref ref;

  Future<void> createSession({
    required String title,
    required String term,
    required int academicYear,
    required String startDate,
    required String endDate,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(examsRepositoryProvider)
          .createSession(
            title: title,
            term: term,
            academicYear: academicYear,
            startDate: startDate,
            endDate: endDate,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(examSessionsProvider);
    }
  }

  Future<void> createPlanning({
    required int session,
    required int classroom,
    required int subject,
    required String examDate,
    required String startTime,
    required String endTime,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(examsRepositoryProvider)
          .createPlanning(
            session: session,
            classroom: classroom,
            subject: subject,
            examDate: examDate,
            startTime: startTime,
            endTime: endTime,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(examPlanningsProvider);
    }
  }

  /// Corrige une campagne, ou la défait.
  ///
  /// Le contrôleur ne savait que créer. Une campagne créée en double le jour
  /// de la rentrée restait donc au registre, et ses épreuves avec.
  Future<void> updateSession({
    required int id,
    String? title,
    String? term,
    String? startDate,
    String? endDate,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(examsRepositoryProvider).updateSession(
        id: id,
        title: title,
        term: term,
        startDate: startDate,
        endDate: endDate,
      ),
    );
    if (!state.hasError) ref.invalidate(examSessionsProvider);
  }

  Future<void> deleteSession(int id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(examsRepositoryProvider).deleteSession(id),
    );
    if (!state.hasError) {
      ref.invalidate(examSessionsProvider);
      ref.invalidate(examPlanningsProvider);
      ref.invalidate(examInvigilationsProvider);
      ref.invalidate(examResultsProvider);
    }
  }

  Future<void> updatePlanning({
    required int id,
    int? classroom,
    int? subject,
    String? examDate,
    String? startTime,
    String? endTime,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(examsRepositoryProvider).updatePlanning(
        id: id,
        classroom: classroom,
        subject: subject,
        examDate: examDate,
        startTime: startTime,
        endTime: endTime,
      ),
    );
    if (!state.hasError) {
      ref.invalidate(examPlanningsProvider);
      ref.invalidate(examSessionsProvider);
    }
  }

  Future<void> deletePlanning(int id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(examsRepositoryProvider).deletePlanning(id),
    );
    if (!state.hasError) {
      ref.invalidate(examPlanningsProvider);
      ref.invalidate(examSessionsProvider);
      ref.invalidate(examInvigilationsProvider);
    }
  }

  Future<void> deleteInvigilation(int id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(examsRepositoryProvider).deleteInvigilation(id),
    );
    if (!state.hasError) ref.invalidate(examInvigilationsProvider);
  }

  /// Ouvre les résultats d'une session aux familles.
  ///
  /// Rend le message du serveur plutôt que rien: l'écran doit pouvoir dire
  /// ce qui s'est passé, y compris un refus (une session sans note).
  Future<String?> publierLesResultats(int sessionId) async {
    state = const AsyncValue.loading();
    String? message;
    state = await AsyncValue.guard(() async {
      message = await ref
          .read(examsRepositoryProvider)
          .publierLesResultats(sessionId);
    });
    if (!state.hasError) {
      ref.invalidate(examSessionsProvider);
      ref.invalidate(examResultsProvider);
    }
    return message;
  }

  Future<String?> retirerLesResultats(int sessionId) async {
    state = const AsyncValue.loading();
    String? message;
    state = await AsyncValue.guard(() async {
      message = await ref
          .read(examsRepositoryProvider)
          .retirerLesResultats(sessionId);
    });
    if (!state.hasError) {
      ref.invalidate(examSessionsProvider);
      ref.invalidate(examResultsProvider);
    }
    return message;
  }

  /// Ouvre une épreuve, et elle seule.
  ///
  /// Invalide aussi les plannings: c'est eux qui portent désormais l'état de
  /// publication, et la liste doit le refléter sans rechargement manuel.
  Future<String?> publierLEpreuve(int planningId) async {
    state = const AsyncValue.loading();
    String? message;
    state = await AsyncValue.guard(() async {
      message = await ref
          .read(examsRepositoryProvider)
          .publierLEpreuve(planningId);
    });
    if (!state.hasError) {
      ref.invalidate(examPlanningsProvider);
      ref.invalidate(examSessionsProvider);
      ref.invalidate(examResultsProvider);
    }
    return message;
  }

  Future<String?> retirerLEpreuve(int planningId) async {
    state = const AsyncValue.loading();
    String? message;
    state = await AsyncValue.guard(() async {
      message = await ref
          .read(examsRepositoryProvider)
          .retirerLEpreuve(planningId);
    });
    if (!state.hasError) {
      ref.invalidate(examPlanningsProvider);
      ref.invalidate(examSessionsProvider);
      ref.invalidate(examResultsProvider);
    }
    return message;
  }

  Future<void> createInvigilation({
    required int planning,
    required int supervisor,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(examsRepositoryProvider)
          .createInvigilation(planning: planning, supervisor: supervisor),
    );
    if (!state.hasError) {
      ref.invalidate(examInvigilationsProvider);
    }
  }
}
