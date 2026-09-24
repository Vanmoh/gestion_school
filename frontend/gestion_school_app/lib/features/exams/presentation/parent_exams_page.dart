import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/exam_models.dart';
import '../domain/parent_exam_grouping.dart';
import 'exams_controller.dart';

/// Les examens vus par la famille : ce qui arrive, et ce qui est arrêté.
///
/// Elle recevait jusqu'ici l'écran d'administration entier, seulement grisé :
/// cinq formulaires de création inertes, le calendrier d'examen de toutes les
/// classes de l'école, le tableau de qui surveille quoi, et la carte de
/// publication annonçant « N note(s) saisie(s), non publiées » pour chaque
/// session — c'est-à-dire l'existence de notes que l'école lui refusait
/// justement de lire.
///
/// Même remède que pour la discipline et les émargements : une page qui ne
/// montre que ce qui la concerne, et qui n'écrit rien. Le cloisonnement
/// lui-même est posé par le serveur — `/exam-results/` ne rend que les notes
/// publiées de ses enfants, `/exam-plannings/` que les épreuves de leurs
/// classes — cette page n'a donc rien à filtrer, seulement à présenter.
class ParentExamsPage extends ConsumerStatefulWidget {
  const ParentExamsPage({super.key});

  @override
  ConsumerState<ParentExamsPage> createState() => _ParentExamsPageState();
}

class _ParentExamsPageState extends ConsumerState<ParentExamsPage> {
  bool _loading = true;
  bool _restricted = false;
  String? _errorMessage;
  List<ExamResultItem> _resultats = const [];
  List<ExamPlanningItem> _epreuves = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final depot = ref.read(examsRepositoryProvider);
      final resultats = await depot.fetchResults();
      final epreuves = await depot.fetchPlannings();
      if (!mounted) return;
      setState(() {
        _resultats = resultats;
        _epreuves = epreuves;
        _restricted = false;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _resultats = const [];
        _epreuves = const [];
        _restricted = status == 401 || status == 403;
        _errorMessage = _restricted
            ? null
            : 'Impossible de charger les examens pour le moment.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resultats = const [];
        _epreuves = const [];
        _restricted = false;
        _errorMessage = 'Impossible de charger les examens pour le moment.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final groupes = grouperLesExamensParEnfant(_resultats);
    final aVenir = epreuvesAVenir(_epreuves, DateTime.now());

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Examens', style: textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Les épreuves à venir et les résultats publiés par '
                      'l\'établissement.',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_errorMessage != null)
            _NoticeCard(
              icon: Icons.error_outline,
              color: colorScheme.error,
              message: _errorMessage!,
            )
          else if (_restricted)
            _NoticeCard(
              icon: Icons.lock_outline,
              color: colorScheme.onSurfaceVariant,
              message:
                  'Les examens ne sont pas accessibles avec vos droits actuels.',
            )
          else ...[
            if (aVenir.isNotEmpty) ...[
              Text('Épreuves à venir', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final epreuve in aVenir)
                _CarteEpreuve(key: ValueKey(epreuve.id), epreuve: epreuve),
              const SizedBox(height: 18),
            ],

            Text('Résultats publiés', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            if (groupes.isEmpty)
              // Ni une erreur ni un vide : une attente. La famille doit
              // savoir que le silence vient du calendrier, pas d'une panne —
              // sans quoi elle appelle le secrétariat.
              _NoticeCard(
                icon: Icons.hourglass_empty_outlined,
                color: colorScheme.onSurfaceVariant,
                message:
                    'Aucun résultat publié pour le moment. Les notes sont '
                    'remises aux familles une fois arrêtées par la direction.',
              )
            else
              for (final groupe in groupes)
                _CarteEnfant(key: ValueKey(groupe.studentId), groupe: groupe),
          ],
        ],
      ),
    );
  }
}

class _CarteEpreuve extends StatelessWidget {
  final ExamPlanningItem epreuve;

  const _CarteEpreuve({super.key, required this.epreuve});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final horaire = [epreuve.startTime, epreuve.endTime]
        .where((valeur) => valeur.trim().isNotEmpty)
        .join(' → ');

    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text(epreuve.examDate, style: textTheme.titleSmall),
        subtitle: horaire.isEmpty ? null : Text(horaire),
      ),
    );
  }
}

class _CarteEnfant extends StatelessWidget {
  final GroupeDExamensParEnfant groupe;

  const _CarteEnfant({super.key, required this.groupe});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final moyenne = groupe.moyenne;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(groupe.nomDeLEnfant, style: textTheme.titleMedium),
            if (groupe.matricule.isNotEmpty)
              Text(groupe.matricule, style: textTheme.bodySmall),
            const SizedBox(height: 10),
            for (final resultat in groupe.resultats)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(resultat.matiere, style: textTheme.bodyMedium),
                          Text(resultat.epreuve, style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text(
                      '${resultat.score.toStringAsFixed(2)} / 20',
                      style: textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            if (moyenne != null) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // « des notes publiées » et non « moyenne » tout court :
                  // ce chiffre ne porte que sur ce qui est affiché, et il ne
                  // remplace pas la moyenne du bulletin, qui compte aussi les
                  // devoirs et les coefficients.
                  Text(
                    'Moyenne des notes publiées',
                    style: textTheme.bodySmall,
                  ),
                  Text(
                    '${moyenne.toStringAsFixed(2)} / 20',
                    style: textTheme.titleSmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
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
