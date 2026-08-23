import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import 'attendance_page.dart';
import 'teacher_timesheet_page.dart';

/// Les deux emargements sous une seule entree: eleves et enseignants.
///
/// Les cles de droits restent separees. Leurs matrices sont incompatibles --
/// le parent lit les absences de son enfant mais rien de l'emargement des
/// enseignants, le comptable l'inverse, le surveillant saisit les absences
/// sans voir l'emargement. Les fondre en une seule cle aurait oblige a choisir
/// laquelle de ces populations perdre.
///
/// Chaque onglet est donc garde par la sienne, et un onglet ferme n'apparait
/// pas: un onglet visible mais vide se lit comme une panne.
class AttendanceModulePage extends ConsumerStatefulWidget {
  const AttendanceModulePage({super.key});

  @override
  ConsumerState<AttendanceModulePage> createState() =>
      _AttendanceModulePageState();
}

class _AttendanceModulePageState extends ConsumerState<AttendanceModulePage>
    with SingleTickerProviderStateMixin {
  TabController? _controller;
  int _nombreOnglets = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Onglets ouverts au profil connecte, dans l'ordre d'affichage.
  List<_Onglet> _ongletsAutorises() {
    final droits = ref.read(currentPermissionsProvider);
    return [
      if (droits.canRead('attendance'))
        const _Onglet(
          cle: 'attendance',
          libelle: 'Élèves',
          icone: Icons.groups_2_outlined,
          vue: AttendancePage(),
        ),
      if (droits.canRead('teacher_timesheet'))
        const _Onglet(
          cle: 'teacher_timesheet',
          libelle: 'Enseignants',
          icone: Icons.access_time_rounded,
          vue: TeacherTimesheetPage(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final onglets = _ongletsAutorises();

    if (onglets.isEmpty) {
      // Ne devrait pas arriver: l'entree de menu n'apparait que si une cle
      // est lisible. Mais un droit revoque en cours de session y menerait.
      return const _AucunAcces();
    }

    // Un seul onglet ouvert: la barre n'aurait rien a proposer.
    if (onglets.length == 1) {
      return onglets.first.vue;
    }

    if (_controller == null || _nombreOnglets != onglets.length) {
      _controller?.dispose();
      _controller = TabController(length: onglets.length, vsync: this);
      _nombreOnglets = onglets.length;
    }

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _controller,
            tabs: [
              for (final onglet in onglets)
                Tab(icon: Icon(onglet.icone), text: onglet.libelle),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: [for (final onglet in onglets) onglet.vue],
          ),
        ),
      ],
    );
  }
}

class _Onglet {
  final String cle;
  final String libelle;
  final IconData icone;
  final Widget vue;

  const _Onglet({
    required this.cle,
    required this.libelle,
    required this.icone,
    required this.vue,
  });
}

class _AucunAcces extends StatelessWidget {
  const _AucunAcces();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Votre profil n’accède à aucun émargement.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
