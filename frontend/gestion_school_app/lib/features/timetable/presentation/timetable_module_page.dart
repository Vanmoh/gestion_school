import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import 'timetable_availability_page.dart';
import 'timetable_page.dart';

/// Les deux temps de l'emploi du temps: le recueil, puis la grille.
///
/// La coque était un **menu déroulant « Section: »** — seul endroit du projet
/// à naviguer ainsi. Un menu déroulant se lit comme un filtre, pas comme une
/// navigation: la page des disponibilités s'y trouvait cachée, et personne ne
/// pensait à l'ouvrir. Sept autres modules se rangent en onglets; celui-ci les
/// rejoint.
///
/// L'ordre suit le travail, comme pour les examens: on recueille les
/// disponibilités des enseignants **avant** de composer la grille. La grille
/// reste en premier onglet parce que c'est elle qu'on consulte toute l'année,
/// une fois la campagne passée.
///
/// Chaque onglet est gardé par sa propre clé de droits — `timetable` et
/// `teacher_availability` ont des matrices distinctes: le comptable et le
/// surveillant lisent la grille sans rien savoir des disponibilités, et
/// l'enseignant déclare les siennes. Un onglet fermé n'apparaît pas: un onglet
/// visible mais vide se lit comme une panne.
class TimetableModulePage extends ConsumerStatefulWidget {
  const TimetableModulePage({super.key});

  @override
  ConsumerState<TimetableModulePage> createState() =>
      _TimetableModulePageState();
}

class _TimetableModulePageState extends ConsumerState<TimetableModulePage>
    with SingleTickerProviderStateMixin {
  TabController? _controleur;
  int _nombreOnglets = 0;

  @override
  void dispose() {
    _controleur?.dispose();
    super.dispose();
  }

  List<_Onglet> _ongletsAutorises() {
    final droits = ref.read(currentPermissionsProvider);
    return [
      if (droits.canRead('timetable'))
        const _Onglet(
          libelle: 'Grille',
          icone: Icons.grid_on_outlined,
          vue: TimetablePage(),
        ),
      if (droits.canRead('teacher_availability'))
        const _Onglet(
          libelle: 'Disponibilités',
          icone: Icons.event_available_outlined,
          vue: TeacherAvailabilityPage(),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final onglets = _ongletsAutorises();

    if (onglets.isEmpty) {
      // Ne devrait pas arriver: l'entrée de menu n'apparaît que si une clé est
      // lisible. Mais un droit révoqué en cours de session y mènerait.
      return const _AucunAcces();
    }

    // Un seul onglet ouvert: la barre n'aurait rien à proposer.
    if (onglets.length == 1) {
      return onglets.first.vue;
    }

    if (_controleur == null || _nombreOnglets != onglets.length) {
      _controleur?.dispose();
      _controleur = TabController(length: onglets.length, vsync: this);
      _nombreOnglets = onglets.length;
    }

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _controleur,
            tabs: [
              for (final onglet in onglets)
                Tab(icon: Icon(onglet.icone), text: onglet.libelle),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controleur,
            children: [for (final onglet in onglets) onglet.vue],
          ),
        ),
      ],
    );
  }
}

class _Onglet {
  final String libelle;
  final IconData icone;
  final Widget vue;

  const _Onglet({
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
            Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Votre profil n\'a accès ni à la grille ni aux disponibilités.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
