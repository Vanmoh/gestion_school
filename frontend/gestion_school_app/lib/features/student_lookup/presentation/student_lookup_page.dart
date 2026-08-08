import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/media_url.dart';
import '../../students/domain/student.dart';
import '../data/student_lookup_repository.dart';
import '../domain/student_dossier.dart';
import 'widgets/dossier_identity_card.dart';
import 'widgets/dossier_sections_panel.dart';

/// Ecran « Recherche élève » : un identifiant, tout le dossier.
///
/// On tape un nom, un matricule ou un telephone, on choisit l'eleve parmi les
/// correspondances, et l'ensemble de ce que l'etablissement sait de lui
/// s'affiche. Volontairement en consultation seule: les modifications passent
/// par le module Gestion des eleves, ou elles sont tracees.
class StudentLookupPage extends ConsumerStatefulWidget {
  /// Ouvre directement le dossier de cet eleve, sans passer par la recherche.
  final int? initialStudentId;

  const StudentLookupPage({super.key, this.initialStudentId});

  @override
  ConsumerState<StudentLookupPage> createState() => _StudentLookupPageState();
}

class _StudentLookupPageState extends ConsumerState<StudentLookupPage> {
  static const _debounce = Duration(milliseconds: 250);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _timer;
  String _query = '';
  bool _searching = false;
  bool _loadingDossier = false;
  String _error = '';
  List<Student>? _results;
  StudentDossier? _dossier;

  /// Identifie la recherche en cours: une reponse lente ne doit pas ecraser
  /// le resultat d'une frappe plus recente.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStudentId;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDossier(initial));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    setState(() {
      _query = query;
      _dossier = null;
      _error = '';
    });

    if (query.isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }

    final ticket = ++_requestId;
    setState(() => _searching = true);

    try {
      final found = await ref
          .read(studentLookupRepositoryProvider)
          .search(query);
      if (!mounted || ticket != _requestId) return;
      setState(() {
        _results = found;
        _searching = false;
      });
      // Une correspondance unique: inutile de faire cliquer pour rien.
      if (found.length == 1) _openDossier(found.first.id);
    } catch (error) {
      if (!mounted || ticket != _requestId) return;
      setState(() {
        _searching = false;
        _results = const [];
        _error = "La recherche n'a pas abouti. Réessayez.";
      });
    }
  }

  Future<void> _openDossier(int studentId) async {
    setState(() {
      _loadingDossier = true;
      _error = '';
    });

    try {
      final dossier = await ref
          .read(studentLookupRepositoryProvider)
          .fetchDossier(studentId);
      if (!mounted) return;
      setState(() {
        _dossier = dossier;
        _loadingDossier = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDossier = false;
        _error = "Ce dossier n'a pas pu être ouvert.";
      });
    }
  }

  void _reset() {
    _timer?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _results = null;
      _dossier = null;
      _error = '';
      _searching = false;
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surfaceContainerLow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SearchBand(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onQueryChanged,
                    onSubmitted: (value) {
                      _timer?.cancel();
                      _search(value);
                    },
                    onClear: _reset,
                    searching: _searching,
                  ),
                  const SizedBox(height: 20),
                  if (_error.isNotEmpty) _ErrorBanner(message: _error),
                  ..._buildBody(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Le stockage objet signe ses liens et renvoie une URL absolue; en local,
  /// l'API sert un chemin relatif qu'il faut resoudre contre sa base.
  String _photoUrl(StudentDossier dossier) {
    return resolveMediaUrl(
      dossier.student.photo,
      ref.read(studentLookupRepositoryProvider).dio.options.baseUrl,
    );
  }

  List<Widget> _buildBody() {
    if (_loadingDossier) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final dossier = _dossier;
    if (dossier != null) {
      return [
        _DossierHeader(
          student: dossier.student,
          onBack: _results != null && _results!.length > 1
              ? () => setState(() => _dossier = null)
              : null,
        ),
        const SizedBox(height: 16),
        _DossierBody(dossier: dossier, photoUrl: _photoUrl(dossier)),
      ];
    }

    final results = _results;
    if (results == null) {
      return const [_IdleHint()];
    }
    if (_searching) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (results.isEmpty) {
      return [_EmptyResults(query: _query)];
    }

    return [
      _ResultsList(students: results, onOpen: (student) => _openDossier(student.id)),
    ];
  }
}

class _SearchBand extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool searching;

  const _SearchBand({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.searching,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.primary.withValues(alpha: 0.02),
          ],
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            'Recherche élève',
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Nom, matricule, classe, parent ou téléphone',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Rechercher un élève…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (controller.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Effacer',
                                onPressed: onClear,
                              )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Icon(Icons.badge_outlined, size: 44, color: scheme.outline),
          const SizedBox(height: 14),
          Text(
            'Saisissez un nom ou un matricule pour ouvrir un dossier',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  final String query;

  const _EmptyResults({required this.query});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.person_search_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            'Aucun élève pour « $query »',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Vérifiez l\'orthographe, ou cherchez par matricule.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  final List<Student> students;
  final ValueChanged<Student> onOpen;

  const _ResultsList({required this.students, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pluriel = students.length > 1 ? 's' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            '${students.length} élève$pluriel trouvé$pluriel',
            style: textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final student in students)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onOpen(student),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: scheme.primaryContainer,
                        child: Icon(
                          Icons.person_outline,
                          size: 18,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student.fullName,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              [
                                if (student.classroomName.isNotEmpty)
                                  student.classroomName,
                                student.matricule,
                              ].join('  ·  '),
                              style: textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (student.isArchived)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            'Archivé',
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const Text('Ouvrir'),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DossierHeader extends StatelessWidget {
  final Student student;
  final VoidCallback? onBack;

  const _DossierHeader({required this.student, this.onBack});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Retour aux résultats',
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student.fullName,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                [
                  student.matricule,
                  if (student.classroomName.isNotEmpty) student.classroomName,
                ].join('  ·  '),
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (student.isArchived)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Archivé',
              style: textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _DossierBody extends StatelessWidget {
  final StudentDossier dossier;
  final String photoUrl;

  const _DossierBody({required this.dossier, this.photoUrl = ''});

  @override
  Widget build(BuildContext context) {
    final identite = DossierIdentityCard(
      student: dossier.student,
      photoUrl: photoUrl,
    );
    final sections = DossierSectionsPanel(sections: dossier.sections);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sous ~900 px les deux colonnes deviennent illisibles: on empile.
        if (constraints.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [identite, const SizedBox(height: 16), sections],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: identite),
            const SizedBox(width: 16),
            Expanded(flex: 5, child: sections),
          ],
        );
      },
    );
  }
}
