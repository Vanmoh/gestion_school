import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annee_scolaire_controller.dart';

/// Ce que l'assistant a repris de l'annee precedente.
class RepriseAnnee {
  final int classes;
  final int matieres;
  final int affectations;
  final int creneaux;

  const RepriseAnnee({
    required this.classes,
    required this.matieres,
    required this.affectations,
    required this.creneaux,
  });

  factory RepriseAnnee.fromJson(Map<String, dynamic> json) {
    int lire(String cle) => (json[cle] as num?)?.toInt() ?? 0;
    return RepriseAnnee(
      classes: lire('classes'),
      matieres: lire('matieres'),
      affectations: lire('affectations'),
      creneaux: lire('creneaux'),
    );
  }

  bool get videE =>
      classes == 0 && matieres == 0 && affectations == 0 && creneaux == 0;
}

/// Ouvrir une annee scolaire en reprenant la structure de la precedente.
///
/// Sans cet ecran, preparer une rentree demandait de ressaisir a la main
/// les classes, leurs matieres, les affectations d'enseignants et tout
/// l'emploi du temps -- pres de quatre cents lignes pour une structure qui
/// change peu d'une annee sur l'autre.
class AssistantOuvertureAnnee extends ConsumerStatefulWidget {
  const AssistantOuvertureAnnee({super.key});

  @override
  ConsumerState<AssistantOuvertureAnnee> createState() =>
      _AssistantOuvertureAnneeState();
}

class _AssistantOuvertureAnneeState
    extends ConsumerState<AssistantOuvertureAnnee> {
  final _nomController = TextEditingController();
  DateTime? _debut;
  DateTime? _fin;

  bool _classes = true;
  bool _matieres = true;
  bool _affectations = true;
  bool _emploiDuTemps = true;
  bool _activer = false;
  bool _cloturerSource = false;

  bool _enCours = false;
  String? _erreur;
  RepriseAnnee? _reprise;

  @override
  void initState() {
    super.initState();
    _proposerLaSuivante();
  }

  /// Pre-remplit avec l'annee qui suit celle en cours.
  ///
  /// « 2025-2026 » appelle « 2026-2027 » aux memes dates decalees d'un an:
  /// laisser l'ecran vide obligerait a retaper ce que le serveur sait deja.
  void _proposerLaSuivante() {
    final courante = ref.read(anneeScolaireProvider).selectionnee;
    if (courante == null) return;

    final debut = DateTime.tryParse(courante.debut);
    final fin = DateTime.tryParse(courante.fin);
    if (debut == null || fin == null) return;

    setState(() {
      _debut = DateTime(debut.year + 1, debut.month, debut.day);
      _fin = DateTime(fin.year + 1, fin.month, fin.day);
      _nomController.text = '${debut.year + 1}-${fin.year + 1}';
    });
  }

  @override
  void dispose() {
    _nomController.dispose();
    super.dispose();
  }

  String _jour(DateTime? date) {
    if (date == null) return 'à choisir';
    final m = date.month.toString().padLeft(2, '0');
    final j = date.day.toString().padLeft(2, '0');
    return '${date.year}-$m-$j';
  }

  Future<void> _choisirDate({required bool debut}) async {
    final initiale = (debut ? _debut : _fin) ?? DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (choisie == null) return;
    setState(() {
      if (debut) {
        _debut = choisie;
      } else {
        _fin = choisie;
      }
    });
  }

  Future<void> _ouvrir() async {
    final nom = _nomController.text.trim();
    if (nom.isEmpty || _debut == null || _fin == null) {
      setState(() => _erreur = 'Renseignez le nom et les deux dates.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    try {
      final resultat = await ref
          .read(anneesScolairesRepositoryProvider)
          .ouvrirAnnee(
            nom: nom,
            debut: _jour(_debut),
            fin: _jour(_fin),
            dupliquerClasses: _classes,
            dupliquerMatieres: _matieres,
            dupliquerAffectations: _affectations,
            dupliquerEmploiDuTemps: _emploiDuTemps,
            activer: _activer,
            cloturerSource: _cloturerSource,
          );

      if (!mounted) return;
      final reprise = resultat['reprise'];
      setState(() {
        _reprise = reprise is Map
            ? RepriseAnnee.fromJson(Map<String, dynamic>.from(reprise))
            : null;
      });

      // La liste des annees a change: le selecteur de la coquille doit la
      // relire, sinon la nouvelle annee n'y figure pas.
      await ref.read(anneeScolaireProvider).charger();
    } catch (error) {
      if (!mounted) return;
      setState(() => _erreur = _messageDErreur(error));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  /// Remonte le message du serveur plutot que la trace technique.
  ///
  /// C'est lui qui dit ce qui bloque -- une periode qui chevauche l'annee
  /// precedente, par exemple -- et l'utilisateur ne peut rien faire d'un
  /// « DioException [bad response] ».
  String _messageDErreur(Object error) {
    if (error is! DioException) {
      return 'L\'ouverture a échoué. Vérifiez les dates saisies.';
    }

    final reponse = error.response;
    if (reponse?.statusCode == 403) {
      return 'L\'ouverture d\'une année est réservée à la direction.';
    }

    // Le corps d'une 400 porte les messages par champ: c'est celui du
    // serveur qu'il faut montrer, lui seul sait ce qui a bloque.
    final corps = reponse?.data;
    if (corps is Map) {
      for (final champ in const [
        'start_date',
        'end_date',
        'name',
        'source_academic_year',
        'detail',
      ]) {
        final valeur = corps[champ];
        if (valeur is List && valeur.isNotEmpty) {
          return valeur.first.toString();
        }
        if (valeur is String && valeur.isNotEmpty) {
          return valeur;
        }
      }
    }

    return 'L\'ouverture a échoué. Vérifiez les dates saisies.';
  }

  @override
  Widget build(BuildContext context) {
    final courante = ref.watch(anneeScolaireProvider).selectionnee;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Ouvrir une année scolaire'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_reprise != null)
                _CompteRendu(reprise: _reprise!)
              else ...[
                Text(
                  courante == null
                      ? 'La structure de l\'année en cours sera reprise.'
                      : 'La structure de ${courante.nom} sera reprise : classes, '
                            'matières, affectations et emploi du temps.',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Les élèves ne sont pas déplacés : leur passage en classe '
                  'supérieure relève de la passation.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('ouverture-nom'),
                  controller: _nomController,
                  decoration: const InputDecoration(
                    labelText: 'Nom de l\'année',
                    hintText: '2026-2027',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        key: const Key('ouverture-debut'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Début'),
                        subtitle: Text(_jour(_debut)),
                        trailing: const Icon(Icons.calendar_month, size: 18),
                        onTap: () => _choisirDate(debut: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ListTile(
                        key: const Key('ouverture-fin'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fin'),
                        subtitle: Text(_jour(_fin)),
                        trailing: const Icon(Icons.calendar_month, size: 18),
                        onTap: () => _choisirDate(debut: false),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Text('Ce qui est repris', style: textTheme.titleSmall),
                // Chaque niveau tient au precedent: une matiere a sa classe,
                // une affectation a sa matiere. Decocher les classes ferme
                // donc tout le reste, et l'ecran le montre plutot que de
                // laisser cocher des cases sans effet.
                CheckboxListTile(
                  key: const Key('ouverture-classes'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _classes,
                  title: const Text('Classes'),
                  onChanged: _enCours
                      ? null
                      : (v) => setState(() => _classes = v ?? true),
                ),
                CheckboxListTile(
                  key: const Key('ouverture-matieres'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _classes && _matieres,
                  title: const Text('Matières'),
                  onChanged: (_enCours || !_classes)
                      ? null
                      : (v) => setState(() => _matieres = v ?? true),
                ),
                CheckboxListTile(
                  key: const Key('ouverture-affectations'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _classes && _matieres && _affectations,
                  title: const Text('Affectations des enseignants'),
                  onChanged: (_enCours || !_classes || !_matieres)
                      ? null
                      : (v) => setState(() => _affectations = v ?? true),
                ),
                CheckboxListTile(
                  key: const Key('ouverture-edt'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _classes && _matieres && _affectations && _emploiDuTemps,
                  title: const Text('Emploi du temps'),
                  onChanged: (_enCours || !_classes || !_matieres || !_affectations)
                      ? null
                      : (v) => setState(() => _emploiDuTemps = v ?? true),
                ),
                const Divider(height: 24),
                CheckboxListTile(
                  key: const Key('ouverture-activer'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _activer,
                  title: const Text('En faire l\'année de saisie'),
                  subtitle: const Text('L\'année en cours cesse de l\'être.'),
                  onChanged: _enCours
                      ? null
                      : (v) => setState(() => _activer = v ?? false),
                ),
                CheckboxListTile(
                  key: const Key('ouverture-cloturer'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _cloturerSource,
                  title: const Text('Clôturer l\'année précédente'),
                  subtitle: const Text(
                    'Elle reste consultable ; seule la direction pourra la corriger.',
                  ),
                  onChanged: _enCours
                      ? null
                      : (v) => setState(() => _cloturerSource = v ?? false),
                ),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(
                  _erreur!,
                  key: const Key('ouverture-erreur'),
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
          child: Text(_reprise == null ? 'Annuler' : 'Fermer'),
        ),
        if (_reprise == null)
          FilledButton(
            key: const Key('ouverture-valider'),
            onPressed: _enCours ? null : _ouvrir,
            child: Text(_enCours ? 'Ouverture…' : 'Ouvrir l\'année'),
          ),
      ],
    );
  }
}

/// Ce que la reprise a produit, ligne par ligne.
///
/// Un simple « opération réussie » ne dirait pas si les quinze classes
/// attendues sont bien la.
class _CompteRendu extends StatelessWidget {
  final RepriseAnnee reprise;

  const _CompteRendu({required this.reprise});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lignes = <(String, int)>[
      ('Classes', reprise.classes),
      ('Matières', reprise.matieres),
      ('Affectations', reprise.affectations),
      ('Créneaux', reprise.creneaux),
    ];

    return Column(
      key: const Key('ouverture-compte-rendu'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'Année ouverte',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (reprise.videE)
          const Text(
            'Aucune structure reprise : l\'année précédente n\'en avait pas, '
            'ou tout a été décoché.',
          )
        else
          for (final (libelle, nombre) in lignes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(width: 150, child: Text(libelle)),
                  Text(
                    '$nombre',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Text(
          'Les élèves n\'ont pas été déplacés. Lancez une passation pour '
          'les faire passer en classe supérieure.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
