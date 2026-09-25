import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../domain/exam_models.dart';
import 'exams_controller.dart';

/// Les épreuves, et où en est la correction de chacune.
///
/// C'est la vue qu'on ouvre en fin de trimestre : quelles copies sont
/// revenues, lesquelles attendent, et lesquelles peuvent être ouvertes aux
/// familles. Le filtre part au serveur — une école de quinze classes
/// déroulait sinon tout son calendrier dans une seule liste.
class OngletCalendrier extends ConsumerStatefulWidget {
  const OngletCalendrier({super.key});

  @override
  ConsumerState<OngletCalendrier> createState() => _OngletCalendrierState();
}

class _OngletCalendrierState extends ConsumerState<OngletCalendrier> {
  FiltreDesEpreuves _filtre = FiltreDesEpreuves.aucun;
  bool _creationDepliee = false;

  int? _sessionId;
  int? _classeId;
  int? _matiereId;
  DateTime _jourDeLEpreuve = DateTime.now();
  TimeOfDay _debut = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _fin = const TimeOfDay(hour: 10, minute: 0);

  void _dire(String message, {bool succes = false, bool erreur = false}) {
    if (!mounted) return;
    ForegroundNotice.show(context, message, isSuccess: succes, isError: erreur);
  }

  String _jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _heure(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  Future<void> _planifier() async {
    if (_sessionId == null || _classeId == null || _matiereId == null) {
      _dire('Choisissez la campagne, la classe et la matière.', erreur: true);
      return;
    }

    await ref
        .read(examMutationProvider.notifier)
        .createPlanning(
          session: _sessionId!,
          classroom: _classeId!,
          subject: _matiereId!,
          examDate: _jour(_jourDeLEpreuve),
          startTime: _heure(_debut),
          endTime: _heure(_fin),
        );

    final etat = ref.read(examMutationProvider);
    if (etat.hasError) {
      // Le serveur dit précisément ce qui ne va pas: épreuve hors de la
      // campagne, matière étrangère à la classe, horaire inversé.
      _dire('Épreuve refusée : ${_motif(etat.error)}', erreur: true);
    } else {
      setState(() => _creationDepliee = false);
      _dire('Épreuve planifiée.', succes: true);
    }
  }

  String _motif(Object? erreur) {
    final texte = erreur?.toString() ?? '';
    return texte.length > 160 ? '${texte.substring(0, 160)}…' : texte;
  }

  Future<void> _supprimer(ExamPlanningItem epreuve) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Supprimer cette épreuve ?'),
        content: Text(
          epreuve.resultatsSaisis > 0
              ? '${epreuve.intitule} porte ${epreuve.resultatsSaisis} '
                    'note(s). Le serveur refusera tant qu\'elles existent.'
              : '${epreuve.intitule} ne porte aucune note.',
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

    await ref.read(examMutationProvider.notifier).deletePlanning(epreuve.id);
    final etat = ref.read(examMutationProvider);
    if (etat.hasError) {
      _dire('Suppression refusée : ${_motif(etat.error)}', erreur: true);
    } else {
      _dire('Épreuve supprimée.', succes: true);
    }
  }

  Future<void> _basculer(ExamPlanningItem epreuve) async {
    final controleur = ref.read(examMutationProvider.notifier);
    final message = epreuve.resultatsPublies
        ? await controleur.retirerLEpreuve(epreuve.id)
        : await controleur.publierLEpreuve(epreuve.id);

    if (ref.read(examMutationProvider).hasError) {
      _dire('Opération refusée par le serveur.', erreur: true);
    } else {
      _dire(message ?? 'Opération effectuée.', succes: true);
    }
  }

  /// Montre ce qu'on s'apprête à publier.
  ///
  /// C'est la question qu'on se pose au moment de cliquer, et rien n'y
  /// répondait : l'ancienne liste « Résultats publiés » affichait tous les
  /// résultats, publiés ou non, sans lien avec l'épreuve.
  Future<void> _ouvrirLesNotes(ExamPlanningItem epreuve) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FenetreDesNotes(epreuve: epreuve),
    );
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final lectureSeule = !droits.canWrite('exams');
    final peutPublier = droits.can(Capacites.publicationDesExamens);
    final epreuvesAsync = ref.watch(examPlanningsProvider(_filtre));
    final sessionsAsync = ref.watch(examSessionsProvider);
    final classesAsync = ref.watch(examClassroomsProvider);
    final mutation = ref.watch(examMutationProvider);

    return Column(
      children: [
        _BarreDeFiltres(
          filtre: _filtre,
          sessionsAsync: sessionsAsync,
          classesAsync: classesAsync,
          onFiltre: (valeur) => setState(() => _filtre = valeur),
          onNouvelle: lectureSeule
              ? null
              : () => setState(() => _creationDepliee = !_creationDepliee),
          creationDepliee: _creationDepliee,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
            children: [
              if (_creationDepliee && !lectureSeule)
                _FormulaireDEpreuve(
                  sessionsAsync: sessionsAsync,
                  classesAsync: classesAsync,
                  sessionId: _sessionId,
                  classeId: _classeId,
                  matiereId: _matiereId,
                  jour: _jourDeLEpreuve,
                  debut: _debut,
                  fin: _fin,
                  enCours: mutation.isLoading,
                  onSession: (v) => setState(() => _sessionId = v),
                  onClasse: (v) => setState(() {
                    _classeId = v;
                    // La matière dépend de la classe: la garder pointerait
                    // sur une matière qu'on n'y enseigne pas.
                    _matiereId = null;
                  }),
                  onMatiere: (v) => setState(() => _matiereId = v),
                  onJour: (v) => setState(() => _jourDeLEpreuve = v),
                  onDebut: (v) => setState(() => _debut = v),
                  onFin: (v) => setState(() => _fin = v),
                  onPlanifier: _planifier,
                ),

              epreuvesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => const _Avis(
                  icone: Icons.error_outline,
                  message: 'Le calendrier n\'a pas pu être chargé.',
                ),
                data: (epreuves) {
                  if (epreuves.isEmpty) {
                    return _Avis(
                      icone: Icons.event_busy_outlined,
                      message: _filtre.estVide
                          ? 'Aucune épreuve planifiée. Créez-en une pour '
                                'inscrire une classe au calendrier.'
                          : 'Aucune épreuve ne correspond à ce filtre.',
                    );
                  }
                  return Column(
                    children: [
                      for (final epreuve in epreuves)
                        _LigneDEpreuve(
                          key: ValueKey('epreuve-${epreuve.id}'),
                          epreuve: epreuve,
                          lectureSeule: lectureSeule,
                          peutPublier: peutPublier,
                          enCours: mutation.isLoading,
                          onOuvrir: () => _ouvrirLesNotes(epreuve),
                          onBasculer: () => _basculer(epreuve),
                          onSupprimer: () => _supprimer(epreuve),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Une épreuve, son état de correction, et le geste qui va avec.
class _LigneDEpreuve extends StatelessWidget {
  final ExamPlanningItem epreuve;
  final bool lectureSeule;
  final bool peutPublier;
  final bool enCours;
  final VoidCallback onOuvrir;
  final VoidCallback onBasculer;
  final VoidCallback onSupprimer;

  const _LigneDEpreuve({
    super.key,
    required this.epreuve,
    required this.lectureSeule,
    required this.peutPublier,
    required this.enCours,
    required this.onOuvrir,
    required this.onBasculer,
    required this.onSupprimer,
  });

  /// Où en est cette épreuve, dit en une phrase.
  ///
  /// « aucune note » et « publiée » sont deux états qu'un booléen seul ne
  /// distinguait pas.
  String get _etat {
    if (epreuve.resultatsPublies) {
      return 'Publiée • ${epreuve.resultatsSaisis} note(s)';
    }
    if (epreuve.resultatsSaisis == 0) return 'Aucune note saisie';
    return '${epreuve.resultatsSaisis} note(s) saisie(s), non publiées';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: epreuve.resultatsSaisis > 0 ? onOuvrir : null,
        title: Text(epreuve.intitule),
        subtitle: Text(
          '${epreuve.examDate} • ${epreuve.startTime} - ${epreuve.endTime}\n'
          '$_etat',
        ),
        isThreeLine: true,
        trailing: lectureSeule
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (peutPublier)
                    epreuve.resultatsPublies
                        ? TextButton(
                            key: ValueKey('retirer-epreuve-${epreuve.id}'),
                            onPressed: enCours ? null : onBasculer,
                            child: const Text('Retirer'),
                          )
                        : FilledButton(
                            key: ValueKey('publier-epreuve-${epreuve.id}'),
                            onPressed: (enCours || !epreuve.peutEtrePubliee)
                                ? null
                                : onBasculer,
                            child: const Text('Publier'),
                          ),
                  IconButton(
                    key: ValueKey('supprimer-epreuve-${epreuve.id}'),
                    tooltip: 'Supprimer',
                    onPressed: enCours ? null : onSupprimer,
                    icon: Icon(Icons.delete_outline, color: scheme.outline),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Les notes d'une épreuve, avant de l'ouvrir aux familles.
class _FenetreDesNotes extends ConsumerWidget {
  final ExamPlanningItem epreuve;

  const _FenetreDesNotes({required this.epreuve});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesDeLEpreuveProvider(epreuve.id));
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(epreuve.intitule),
      content: SizedBox(
        width: 460,
        child: notesAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => const Text('Les notes n\'ont pas pu être lues.'),
          data: (notes) {
            if (notes.isEmpty) {
              return const Text('Aucune note saisie pour cette épreuve.');
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${notes.length} note(s). '
                    '${epreuve.resultatsPublies ? "Déjà publiées." : "Non publiées : les familles ne les voient pas."}',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  for (final note in notes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              note.studentFullName.trim().isEmpty
                                  ? 'Élève'
                                  : note.studentFullName,
                              style: textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            '${note.score.toStringAsFixed(2)} / 20',
                            style: textTheme.titleSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _BarreDeFiltres extends StatelessWidget {
  final FiltreDesEpreuves filtre;
  final AsyncValue<List<ExamSessionItem>> sessionsAsync;
  final AsyncValue<List<OptionItem>> classesAsync;
  final ValueChanged<FiltreDesEpreuves> onFiltre;
  final VoidCallback? onNouvelle;
  final bool creationDepliee;

  const _BarreDeFiltres({
    required this.filtre,
    required this.sessionsAsync,
    required this.classesAsync,
    required this.onFiltre,
    required this.onNouvelle,
    required this.creationDepliee,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: sessionsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (sessions) => DropdownButtonFormField<int?>(
                key: const Key('filtre-campagne'),
                isExpanded: true,
                initialValue: filtre.sessionId,
                decoration: const InputDecoration(
                  labelText: 'Campagne',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Toutes'),
                  ),
                  for (final session in sessions)
                    DropdownMenuItem<int?>(
                      value: session.id,
                      child: Text('${session.title} • ${session.term}'),
                    ),
                ],
                onChanged: (valeur) => onFiltre(
                  valeur == null
                      ? filtre.avec(viderSession: true)
                      : filtre.avec(sessionId: valeur),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: classesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (classes) => DropdownButtonFormField<int?>(
                key: const Key('filtre-classe'),
                isExpanded: true,
                initialValue: filtre.classroomId,
                decoration: const InputDecoration(
                  labelText: 'Classe',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Toutes'),
                  ),
                  for (final classe in classes)
                    DropdownMenuItem<int?>(
                      value: classe.id,
                      child: Text(classe.label),
                    ),
                ],
                onChanged: (valeur) => onFiltre(
                  valeur == null
                      ? filtre.avec(viderClasse: true)
                      : filtre.avec(classroomId: valeur),
                ),
              ),
            ),
          ),
          // Le filtre que la direction utilise en fin de trimestre: ce qui
          // reste à ouvrir.
          FilterChip(
            key: const Key('filtre-a-publier'),
            label: const Text('Reste à publier'),
            selected: filtre.publiees == false,
            onSelected: (choisi) => onFiltre(
              choisi
                  ? filtre.avec(publiees: false)
                  : filtre.avec(viderPublication: true),
            ),
          ),
          if (!filtre.estVide)
            OutlinedButton.icon(
              key: const Key('reinitialiser-filtres'),
              onPressed: () => onFiltre(FiltreDesEpreuves.aucun),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Réinitialiser'),
            ),
          if (onNouvelle != null)
            FilledButton.tonalIcon(
              key: const Key('basculer-creation-epreuve'),
              onPressed: onNouvelle,
              icon: Icon(creationDepliee ? Icons.close : Icons.add, size: 18),
              label: Text(creationDepliee ? 'Fermer' : 'Planifier'),
            ),
        ],
      ),
    );
  }
}

class _FormulaireDEpreuve extends ConsumerWidget {
  final AsyncValue<List<ExamSessionItem>> sessionsAsync;
  final AsyncValue<List<OptionItem>> classesAsync;
  final int? sessionId;
  final int? classeId;
  final int? matiereId;
  final DateTime jour;
  final TimeOfDay debut;
  final TimeOfDay fin;
  final bool enCours;
  final ValueChanged<int?> onSession;
  final ValueChanged<int?> onClasse;
  final ValueChanged<int?> onMatiere;
  final ValueChanged<DateTime> onJour;
  final ValueChanged<TimeOfDay> onDebut;
  final ValueChanged<TimeOfDay> onFin;
  final VoidCallback onPlanifier;

  const _FormulaireDEpreuve({
    required this.sessionsAsync,
    required this.classesAsync,
    required this.sessionId,
    required this.classeId,
    required this.matiereId,
    required this.jour,
    required this.debut,
    required this.fin,
    required this.enCours,
    required this.onSession,
    required this.onClasse,
    required this.onMatiere,
    required this.onJour,
    required this.onDebut,
    required this.onFin,
    required this.onPlanifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matieresAsync = ref.watch(examSubjectsProvider(classeId));

    return Card(
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sessionsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Campagnes indisponibles'),
              data: (sessions) => sessions.isEmpty
                  ? const Text('Créez d\'abord une campagne')
                  : DropdownButtonFormField<int>(
                      key: const Key('epreuve-campagne'),
                      isExpanded: true,
                      initialValue: sessionId,
                      decoration: const InputDecoration(labelText: 'Campagne'),
                      items: [
                        for (final session in sessions)
                          DropdownMenuItem(
                            value: session.id,
                            child: Text('${session.title} • ${session.term}'),
                          ),
                      ],
                      onChanged: onSession,
                    ),
            ),
            const SizedBox(height: 10),
            classesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Classes indisponibles'),
              data: (classes) => DropdownButtonFormField<int>(
                key: const Key('epreuve-classe'),
                isExpanded: true,
                initialValue: classeId,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: [
                  for (final classe in classes)
                    DropdownMenuItem(
                      value: classe.id,
                      child: Text(classe.label),
                    ),
                ],
                onChanged: onClasse,
              ),
            ),
            const SizedBox(height: 10),
            matieresAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => const Text('Matières indisponibles'),
              data: (matieres) => matieres.isEmpty
                  ? const Text('Choisissez d\'abord une classe')
                  : DropdownButtonFormField<int>(
                      key: const Key('epreuve-matiere'),
                      isExpanded: true,
                      initialValue: matiereId,
                      decoration: const InputDecoration(labelText: 'Matière'),
                      items: [
                        for (final matiere in matieres)
                          DropdownMenuItem(
                            value: matiere.id,
                            child: Text(matiere.label),
                          ),
                      ],
                      onChanged: onMatiere,
                    ),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Jour de l\'épreuve'),
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
                if (choisi != null) onJour(choisi);
              },
            ),
            Row(
              children: [
                Expanded(
                  child: _ChoixDHeure(
                    libelle: 'Début',
                    heure: debut,
                    onChange: onDebut,
                  ),
                ),
                Expanded(
                  child: _ChoixDHeure(
                    libelle: 'Fin',
                    heure: fin,
                    onChange: onFin,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              key: const Key('planifier-epreuve'),
              onPressed: enCours ? null : onPlanifier,
              child: const Text('Planifier l\'épreuve'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoixDHeure extends StatelessWidget {
  final String libelle;
  final TimeOfDay heure;
  final ValueChanged<TimeOfDay> onChange;

  const _ChoixDHeure({
    required this.libelle,
    required this.heure,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(libelle),
      subtitle: Text(
        '${heure.hour.toString().padLeft(2, '0')}:'
        '${heure.minute.toString().padLeft(2, '0')}',
      ),
      trailing: const Icon(Icons.schedule_outlined, size: 18),
      onTap: () async {
        final choisi = await showTimePicker(
          context: context,
          initialTime: heure,
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
