import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../domain/exam_models.dart';
import 'exams_controller.dart';

/// Les campagnes d'examen, et où en est chacune.
///
/// L'ancien écran affichait deux fois les sessions — une carte de publication
/// en haut, une liste morte en bas — et le formulaire de création occupait la
/// page en permanence, y compris pour un profil qui ne crée rien.
class OngletCampagnes extends ConsumerStatefulWidget {
  const OngletCampagnes({super.key});

  @override
  ConsumerState<OngletCampagnes> createState() => _OngletCampagnesState();
}

class _OngletCampagnesState extends ConsumerState<OngletCampagnes> {
  bool _creationDepliee = false;

  final _titreController = TextEditingController();
  String _periode = 'T1';
  int? _anneeId;
  DateTime _debut = DateTime.now();
  DateTime _fin = DateTime.now().add(const Duration(days: 3));

  @override
  void dispose() {
    _titreController.dispose();
    super.dispose();
  }

  void _dire(String message, {bool succes = false, bool erreur = false}) {
    if (!mounted) return;
    ForegroundNotice.show(
      context,
      message,
      isSuccess: succes,
      isError: erreur,
    );
  }

  String _jour(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _creer() async {
    final titre = _titreController.text.trim();
    // Un `return` muet laissait l'utilisateur appuyer sans rien obtenir et
    // sans savoir pourquoi.
    if (titre.isEmpty) {
      _dire('Donnez un titre à la campagne.', erreur: true);
      return;
    }
    if (_anneeId == null) {
      _dire('Choisissez une année scolaire.', erreur: true);
      return;
    }
    if (_fin.isBefore(_debut)) {
      _dire('La campagne ne peut pas finir avant de commencer.', erreur: true);
      return;
    }

    await ref
        .read(examMutationProvider.notifier)
        .createSession(
          title: titre,
          term: _periode,
          academicYear: _anneeId!,
          startDate: _jour(_debut),
          endDate: _jour(_fin),
        );

    if (!ref.read(examMutationProvider).hasError) {
      _titreController.clear();
      setState(() => _creationDepliee = false);
      _dire('Campagne « $titre » créée.', succes: true);
    }
  }

  Future<void> _supprimer(ExamSessionItem session) async {
    final depot = ref.read(examsRepositoryProvider);
    InventaireDeSuppression inventaire;
    try {
      inventaire = await depot.inventaireDeLaSession(session.id);
    } catch (_) {
      _dire('Impossible de lire ce que la suppression emporterait.',
          erreur: true);
      return;
    }
    if (!mounted) return;

    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Supprimer cette campagne ?'),
        content: Text(
          inventaire.estVide
              ? '« ${session.title} » ne porte encore rien.'
              : '« ${session.title} » emporte ${inventaire.resume}.\n\n'
                    'Les notes déjà imprimées sur des bulletins ne seront '
                    'plus retrouvables.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    await ref.read(examMutationProvider.notifier).deleteSession(session.id);
    if (ref.read(examMutationProvider).hasError) {
      _dire('Suppression refusée.', erreur: true);
    } else {
      _dire('Campagne supprimée.', succes: true);
    }
  }

  Future<void> _basculerLaPublication(
    ExamSessionItem session, {
    required bool publier,
  }) async {
    if (!publier) {
      final confirme = await showDialog<bool>(
        context: context,
        builder: (contexte) => AlertDialog(
          title: const Text('Retirer les résultats ?'),
          content: Text(
            'Les familles cesseront de voir les notes de '
            '« ${session.title} ». La trace de la première publication reste.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexte).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(contexte).pop(true),
              child: const Text('Retirer'),
            ),
          ],
        ),
      );
      if (confirme != true) return;
    }

    final controleur = ref.read(examMutationProvider.notifier);
    final message = publier
        ? await controleur.publierLesResultats(session.id)
        : await controleur.retirerLesResultats(session.id);

    if (ref.read(examMutationProvider).hasError) {
      _dire('Opération refusée par le serveur.', erreur: true);
    } else {
      _dire(message ?? 'Opération effectuée.', succes: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final lectureSeule = !droits.canWrite('exams');
    final peutPublier = droits.can(Capacites.publicationDesExamens);
    final sessionsAsync = ref.watch(examSessionsProvider);
    final anneesAsync = ref.watch(examAcademicYearsProvider);
    final mutation = ref.watch(examMutationProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        if (!lectureSeule) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('basculer-creation-campagne'),
              onPressed: () =>
                  setState(() => _creationDepliee = !_creationDepliee),
              icon: Icon(
                _creationDepliee ? Icons.close : Icons.add,
                size: 18,
              ),
              label: Text(
                _creationDepliee ? 'Fermer' : 'Nouvelle campagne',
              ),
            ),
          ),
          if (_creationDepliee)
            _FormulaireDeCampagne(
              titreController: _titreController,
              periode: _periode,
              anneeId: _anneeId,
              debut: _debut,
              fin: _fin,
              anneesAsync: anneesAsync,
              enCours: mutation.isLoading,
              onPeriode: (valeur) => setState(() => _periode = valeur),
              onAnnee: (valeur) => setState(() => _anneeId = valeur),
              onDebut: (valeur) => setState(() => _debut = valeur),
              onFin: (valeur) => setState(() => _fin = valeur),
              onCreer: _creer,
            ),
          const SizedBox(height: 14),
        ],

        sessionsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (erreur, _) => _Avis(
            icone: Icons.error_outline,
            message: 'Les campagnes n\'ont pas pu être chargées.',
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return const _Avis(
                icone: Icons.campaign_outlined,
                message: 'Aucune campagne d\'examen. Créez-en une pour '
                    'planifier les épreuves du trimestre.',
              );
            }
            return Column(
              children: [
                for (final session in sessions)
                  _CarteDeCampagne(
                    key: ValueKey('campagne-${session.id}'),
                    session: session,
                    lectureSeule: lectureSeule,
                    peutPublier: peutPublier,
                    enCours: mutation.isLoading,
                    onPublier: () =>
                        _basculerLaPublication(session, publier: true),
                    onRetirer: () =>
                        _basculerLaPublication(session, publier: false),
                    onSupprimer: () => _supprimer(session),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CarteDeCampagne extends StatelessWidget {
  final ExamSessionItem session;
  final bool lectureSeule;
  final bool peutPublier;
  final bool enCours;
  final VoidCallback onPublier;
  final VoidCallback onRetirer;
  final VoidCallback onSupprimer;

  const _CarteDeCampagne({
    super.key,
    required this.session,
    required this.lectureSeule,
    required this.peutPublier,
    required this.enCours,
    required this.onPublier,
    required this.onRetirer,
    required this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final toutPublie =
        session.epreuvesTotal > 0 &&
        session.epreuvesPubliees == session.epreuvesTotal;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.title, style: textTheme.titleMedium),
                      Text(
                        '${session.term} • ${session.startDate} → '
                        '${session.endDate}',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (!lectureSeule)
                  IconButton(
                    key: ValueKey('supprimer-campagne-${session.id}'),
                    tooltip: 'Supprimer',
                    onPressed: enCours ? null : onSupprimer,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Un compte, pas un booléen: « publiée » devant trois épreuves
            // ouvertes sur sept serait faux, et c'est l'état où une campagne
            // passe le plus clair de son temps.
            Text(
              '${session.epreuvesPubliees}/${session.epreuvesTotal} '
              'épreuve(s) publiée(s) • ${session.resultatsSaisis} note(s)',
              style: textTheme.bodyMedium?.copyWith(
                color: toutPublie ? scheme.primary : null,
              ),
            ),
            if (peutPublier && !lectureSeule) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: session.resultatsPublies || toutPublie
                    ? OutlinedButton.icon(
                        key: ValueKey('tout-retirer-${session.id}'),
                        onPressed: enCours ? null : onRetirer,
                        icon: const Icon(
                          Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        label: const Text('Tout retirer'),
                      )
                    : FilledButton.tonalIcon(
                        key: ValueKey('tout-publier-${session.id}'),
                        // Publier le vide ferait chercher aux familles des
                        // résultats qui n'existent pas.
                        onPressed: (enCours || !session.peutEtrePubliee)
                            ? null
                            : onPublier,
                        icon: const Icon(Icons.campaign_outlined, size: 18),
                        label: const Text('Tout publier'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FormulaireDeCampagne extends StatelessWidget {
  final TextEditingController titreController;
  final String periode;
  final int? anneeId;
  final DateTime debut;
  final DateTime fin;
  final AsyncValue<List<OptionItem>> anneesAsync;
  final bool enCours;
  final ValueChanged<String> onPeriode;
  final ValueChanged<int?> onAnnee;
  final ValueChanged<DateTime> onDebut;
  final ValueChanged<DateTime> onFin;
  final VoidCallback onCreer;

  const _FormulaireDeCampagne({
    required this.titreController,
    required this.periode,
    required this.anneeId,
    required this.debut,
    required this.fin,
    required this.anneesAsync,
    required this.enCours,
    required this.onPeriode,
    required this.onAnnee,
    required this.onDebut,
    required this.onFin,
    required this.onCreer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('titre-campagne'),
              controller: titreController,
              decoration: const InputDecoration(
                labelText: 'Titre',
                hintText: 'Composition du premier trimestre',
              ),
            ),
            const SizedBox(height: 10),
            anneesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Années indisponibles'),
              data: (annees) {
                if (annees.isEmpty) {
                  return const Text('Aucune année scolaire');
                }
                final valeur = anneeId ?? annees.first.id;
                if (anneeId == null) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => onAnnee(valeur),
                  );
                }
                return DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: valeur,
                  decoration: const InputDecoration(
                    labelText: 'Année scolaire',
                  ),
                  items: [
                    for (final annee in annees)
                      DropdownMenuItem(
                        value: annee.id,
                        child: Text(annee.label),
                      ),
                  ],
                  onChanged: onAnnee,
                );
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: periode,
              decoration: const InputDecoration(labelText: 'Période'),
              items: const [
                DropdownMenuItem(value: 'T1', child: Text('T1')),
                DropdownMenuItem(value: 'T2', child: Text('T2')),
                DropdownMenuItem(value: 'T3', child: Text('T3')),
              ],
              onChanged: (valeur) => onPeriode(valeur ?? 'T1'),
            ),
            const SizedBox(height: 10),
            _ChoixDeJour(
              libelle: 'Début',
              jour: debut,
              onChange: onDebut,
            ),
            _ChoixDeJour(libelle: 'Fin', jour: fin, onChange: onFin),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('creer-campagne'),
              onPressed: enCours ? null : onCreer,
              child: const Text('Créer la campagne'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoixDeJour extends StatelessWidget {
  final String libelle;
  final DateTime jour;
  final ValueChanged<DateTime> onChange;

  const _ChoixDeJour({
    required this.libelle,
    required this.jour,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(libelle),
      subtitle: Text(
        '${jour.year}-${jour.month.toString().padLeft(2, '0')}-'
        '${jour.day.toString().padLeft(2, '0')}',
      ),
      trailing: const Icon(Icons.calendar_today_outlined, size: 18),
      onTap: () async {
        final choisi = await showDatePicker(
          context: context,
          initialDate: jour,
          firstDate: DateTime(jour.year - 2),
          lastDate: DateTime(jour.year + 2),
        );
        if (choisi != null) onChange(choisi);
      },
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
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          children: [
            Icon(icone, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
