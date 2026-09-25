import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../domain/exam_models.dart';
import 'exams_controller.dart';

/// Qui surveille quoi — et surtout, ce que personne ne surveille.
///
/// L'ancien écran listait les affectations et rien d'autre : une épreuve
/// oubliée ne se voyait nulle part, alors que c'est la seule question qu'on
/// se pose la veille des compositions. Les épreuves sans surveillant passent
/// donc en tête.
///
/// Les libellés d'épreuve y portent enfin leur classe et leur matière ; ils
/// n'affichaient qu'un numéro, une date et deux horaires.
class OngletSurveillance extends ConsumerStatefulWidget {
  const OngletSurveillance({super.key});

  @override
  ConsumerState<OngletSurveillance> createState() =>
      _OngletSurveillanceState();
}

class _OngletSurveillanceState extends ConsumerState<OngletSurveillance> {
  int? _epreuveId;
  int? _surveillantId;

  void _dire(String message, {bool succes = false, bool erreur = false}) {
    if (!mounted) return;
    ForegroundNotice.show(context, message, isSuccess: succes, isError: erreur);
  }

  Future<void> _affecter() async {
    if (_epreuveId == null || _surveillantId == null) {
      _dire('Choisissez l\'épreuve et le surveillant.', erreur: true);
      return;
    }

    await ref
        .read(examMutationProvider.notifier)
        .createInvigilation(
          planning: _epreuveId!,
          supervisor: _surveillantId!,
        );

    if (ref.read(examMutationProvider).hasError) {
      _dire('Affectation refusée. Ce surveillant tient peut-être déjà cette '
          'épreuve.', erreur: true);
    } else {
      _dire('Surveillant affecté.', succes: true);
    }
  }

  Future<void> _retirer(ExamInvigilationItem affectation) async {
    await ref
        .read(examMutationProvider.notifier)
        .deleteInvigilation(affectation.id);

    if (ref.read(examMutationProvider).hasError) {
      _dire('Retrait refusé.', erreur: true);
    } else {
      _dire('Surveillant retiré.', succes: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final lectureSeule = !droits.canWrite('exams');
    final epreuvesAsync = ref.watch(
      examPlanningsProvider(FiltreDesEpreuves.aucun),
    );
    final affectationsAsync = ref.watch(examInvigilationsProvider);
    final surveillantsAsync = ref.watch(examSupervisorsProvider);
    final mutation = ref.watch(examMutationProvider);
    final textTheme = Theme.of(context).textTheme;

    final epreuves = epreuvesAsync.valueOrNull ?? const <ExamPlanningItem>[];
    final affectations =
        affectationsAsync.valueOrNull ?? const <ExamInvigilationItem>[];
    final epreuveParId = {for (final e in epreuves) e.id: e};
    final tenues = affectations.map((a) => a.planningId).toSet();
    final sansPersonne = epreuves
        .where((epreuve) => !tenues.contains(epreuve.id))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        // En tête, ce qui manque: c'est ce qu'on vient vérifier.
        Text('Épreuves sans surveillant', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        if (epreuvesAsync.isLoading || affectationsAsync.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (epreuves.isEmpty)
          const _Avis(
            icone: Icons.event_busy_outlined,
            message: 'Aucune épreuve planifiée.',
          )
        else if (sansPersonne.isEmpty)
          const _Avis(
            icone: Icons.verified_outlined,
            message: 'Toutes les épreuves ont un surveillant.',
          )
        else
          for (final epreuve in sansPersonne)
            Card(
              key: ValueKey('sans-surveillant-${epreuve.id}'),
              child: ListTile(
                leading: Icon(
                  Icons.report_problem_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(epreuve.intitule),
                subtitle: Text(
                  '${epreuve.examDate} • ${epreuve.startTime} - '
                  '${epreuve.endTime}',
                ),
              ),
            ),

        const SizedBox(height: 22),

        if (!lectureSeule) ...[
          Text('Affecter un surveillant', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  epreuves.isEmpty
                      ? const Text('Planifiez d\'abord une épreuve')
                      : DropdownButtonFormField<int>(
                          key: const Key('surveillance-epreuve'),
                          isExpanded: true,
                          initialValue: _epreuveId,
                          decoration: const InputDecoration(
                            labelText: 'Épreuve',
                          ),
                          items: [
                            for (final epreuve in epreuves)
                              DropdownMenuItem(
                                value: epreuve.id,
                                child: Text(
                                  '${epreuve.intitule} • ${epreuve.examDate}',
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _epreuveId = v),
                        ),
                  const SizedBox(height: 10),
                  surveillantsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => const Text('Surveillants indisponibles'),
                    data: (surveillants) => surveillants.isEmpty
                        ? const Text(
                            'Aucun compte de surveillance disponible',
                          )
                        : DropdownButtonFormField<int>(
                            key: const Key('surveillance-personne'),
                            isExpanded: true,
                            initialValue: _surveillantId,
                            decoration: const InputDecoration(
                              labelText: 'Surveillant',
                            ),
                            items: [
                              for (final personne in surveillants)
                                DropdownMenuItem(
                                  value: personne.id,
                                  child: Text(personne.label),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _surveillantId = v),
                          ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    key: const Key('affecter-surveillant'),
                    onPressed: mutation.isLoading ? null : _affecter,
                    child: const Text('Affecter'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],

        Text('Affectations', style: textTheme.titleMedium),
        const SizedBox(height: 8),
        affectationsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => const _Avis(
            icone: Icons.error_outline,
            message: 'Les affectations n\'ont pas pu être chargées.',
          ),
          data: (lignes) {
            if (lignes.isEmpty) {
              return const _Avis(
                icone: Icons.visibility_off_outlined,
                message: 'Aucun surveillant affecté.',
              );
            }
            return Column(
              children: [
                for (final affectation in lignes)
                  Card(
                    key: ValueKey('affectation-${affectation.id}'),
                    child: ListTile(
                      title: Text(affectation.supervisorName),
                      // L'épreuve se nomme par sa classe et sa matière; elle
                      // n'affichait qu'un numéro que personne ne connaît.
                      subtitle: Text(
                        epreuveParId[affectation.planningId]?.intitule ??
                            'Épreuve retirée',
                      ),
                      trailing: lectureSeule
                          ? null
                          : IconButton(
                              key: ValueKey(
                                'retirer-affectation-${affectation.id}',
                              ),
                              tooltip: 'Retirer',
                              onPressed: mutation.isLoading
                                  ? null
                                  : () => _retirer(affectation),
                              icon: const Icon(Icons.person_remove_outlined),
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Avis extends StatelessWidget {
  final IconData icone;
  final String message;

  const _Avis({required this.icone, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        child: Row(
          children: [
            Icon(icone, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
