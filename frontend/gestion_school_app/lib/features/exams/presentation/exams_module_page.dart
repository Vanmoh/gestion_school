import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/indicateur.dart';
import '../../imports/presentation/academic_imports_window.dart';
import '../../../core/theme/academic_imports_ui_reference.dart';
import 'exams_controller.dart';
import 'onglet_calendrier.dart';
import 'onglet_campagnes.dart';
import 'onglet_surveillance.dart';

/// Les examens, rangés par la question qu'on se pose et non par table.
///
/// L'écran empilait quatre formulaires et quatre listes, calqués un pour un
/// sur les quatre ViewSets du backend : créer une session, publier, créer un
/// planning, attribuer un surveillant, puis quatre listes dont trois
/// redisaient ce qui précédait. Un censeur y voyait la plomberie du module,
/// pas son travail.
///
/// Son travail suit l'ordre que `docs/PROCEDURE_DE_RENTREE.md` décrit :
/// préparer la campagne, planifier les épreuves, les faire surveiller, puis —
/// après correction — publier. Un onglet par étape, dans cet ordre.
class ExamsModulePage extends ConsumerStatefulWidget {
  const ExamsModulePage({super.key});

  @override
  ConsumerState<ExamsModulePage> createState() => _ExamsModulePageState();
}

class _ExamsModulePageState extends ConsumerState<ExamsModulePage>
    with SingleTickerProviderStateMixin {
  late final TabController _controleur = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _toutRecharger() {
    ref.invalidate(examSessionsProvider);
    ref.invalidate(examPlanningsProvider);
    ref.invalidate(examInvigilationsProvider);
    ref.invalidate(examResultsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final lectureSeule = !droits.canWrite('exams');

    return Column(
      children: [
        _EnTete(
          lectureSeule: lectureSeule,
          onRecharger: _toutRecharger,
          peutImporter: !lectureSeule,
        ),
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _controleur,
            tabs: const [
              Tab(icon: Icon(Icons.campaign_outlined), text: 'Campagnes'),
              Tab(icon: Icon(Icons.event_note_outlined), text: 'Calendrier'),
              Tab(icon: Icon(Icons.visibility_outlined), text: 'Surveillance'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controleur,
            children: const [
              OngletCampagnes(),
              OngletCalendrier(),
              OngletSurveillance(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Le titre, l'état des lieux, et les deux gestes qui valent pour tout l'écran.
///
/// Les compteurs restent au-dessus des onglets plutôt que dans l'un d'eux :
/// ils décrivent la campagne entière, et les chercher dans un onglet
/// obligerait à en changer pour savoir où l'on en est.
class _EnTete extends ConsumerWidget {
  final bool lectureSeule;
  final VoidCallback onRecharger;
  final bool peutImporter;

  const _EnTete({
    required this.lectureSeule,
    required this.onRecharger,
    required this.peutImporter,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final sessions = ref.watch(examSessionsProvider).valueOrNull;
    final epreuves = ref
        .watch(examPlanningsProvider(FiltreDesEpreuves.aucun))
        .valueOrNull;

    // Nuls tant que les requêtes n'ont pas répondu: la ligne affiche alors
    // une attente, et non un zéro qu'on lirait comme un registre vide.
    final aPublier = epreuves
        ?.where((epreuve) => epreuve.peutEtrePubliee)
        .length;
    final publiees = epreuves
        ?.where((epreuve) => epreuve.resultatsPublies)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
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
                    Text('Examens', style: textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      lectureSeule
                          ? 'Consultation seule : votre profil ne peut pas '
                                'modifier ce module.'
                          : 'Préparer les campagnes, planifier les épreuves, '
                                'puis publier classe par classe.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onRecharger,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualiser'),
                  ),
                  OutlinedButton.icon(
                    onPressed: peutImporter
                        ? () => showAcademicImportsFloatingWindow(context)
                        : null,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Imports académiques'),
                    style: AcademicImportsUiReference.importActionStyle(
                      Theme.of(context).colorScheme,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Indicateur(
                libelle: 'Campagnes',
                valeur: sessions == null ? '—' : '${sessions.length}',
              ),
              Indicateur(
                libelle: 'Épreuves',
                valeur: epreuves == null ? '—' : '${epreuves.length}',
              ),
              Indicateur(
                libelle: 'Publiées',
                valeur: publiees == null ? '—' : '$publiees',
              ),
              // Le chiffre que la direction cherche en fin de trimestre: ce
              // qui est corrigé et attend encore d'être ouvert aux familles.
              Indicateur(
                libelle: 'Prêtes à publier',
                valeur: aPublier == null ? '—' : '$aPublier',
                couleur: (aPublier ?? 0) > 0
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
