import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/indicateur.dart';
import 'communication_controller.dart';
import 'onglet_annonces.dart';
import 'onglet_notifications.dart';
import 'onglet_passerelle_sms.dart';

/// La communication, rangée par destinataire et non par table.
///
/// L'écran empilait trois formulaires et trois listes, calqués un pour un sur
/// ses trois ViewSets: rédiger une annonce, créer une notification, configurer
/// le SMS, puis les trois listes correspondantes — cherchées en mémoire par
/// une seule barre de recherche partagée, sur la page déjà chargée.
///
/// Trois questions, trois onglets: ce que l'école a annoncé, ce qui est parti
/// aux personnes, et par quel tuyau les SMS sortent. Le troisième est gardé
/// par `sms_config`, clé séparée de `communication` dans la matrice parce que
/// la configuration porte le jeton d'API du fournisseur en clair.
class CommunicationModulePage extends ConsumerStatefulWidget {
  const CommunicationModulePage({super.key});

  @override
  ConsumerState<CommunicationModulePage> createState() =>
      _CommunicationModulePageState();
}

class _CommunicationModulePageState
    extends ConsumerState<CommunicationModulePage>
    with SingleTickerProviderStateMixin {
  TabController? _controleur;
  int _nombreOnglets = 0;

  @override
  void dispose() {
    _controleur?.dispose();
    super.dispose();
  }

  void _toutRecharger() {
    ref.invalidate(annoncesProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(passerellesSmsProvider);
    ref.invalidate(destinatairesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final lectureSeule = !droits.canWrite('communication');

    final onglets = <_Onglet>[
      const _Onglet(
        libelle: 'Annonces',
        icone: Icons.campaign_outlined,
        vue: OngletAnnonces(),
      ),
      const _Onglet(
        libelle: 'Notifications',
        icone: Icons.notifications_outlined,
        vue: OngletNotifications(),
      ),
      // Un onglet fermé n'apparaît pas: un onglet visible mais vide se lit
      // comme une panne.
      if (droits.canRead('sms_config'))
        const _Onglet(
          libelle: 'Passerelle SMS',
          icone: Icons.cell_tower,
          vue: OngletPasserelleSms(),
        ),
    ];

    if (_controleur == null || _nombreOnglets != onglets.length) {
      _controleur?.dispose();
      _controleur = TabController(length: onglets.length, vsync: this);
      _nombreOnglets = onglets.length;
    }

    return Column(
      children: [
        _EnTete(lectureSeule: lectureSeule, onRecharger: _toutRecharger),
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

/// Le titre, l'état des lieux, et le geste qui vaut pour tout l'écran.
class _EnTete extends ConsumerWidget {
  final bool lectureSeule;
  final VoidCallback onRecharger;

  const _EnTete({required this.lectureSeule, required this.onRecharger});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final annonces = ref.watch(annoncesProvider(FiltreDesAnnonces.aucun)).valueOrNull;
    final notifications = ref
        .watch(notificationsProvider(FiltreDesNotifications.aucun))
        .valueOrNull;

    // Nuls tant que les requêtes n'ont pas répondu: la ligne affiche alors
    // une attente, et non un zéro qu'on lirait comme un registre vide.
    final enAttente =
        notifications?.where((ligne) => !ligne.envoyee).length;

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
                    Text('Communication', style: textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      lectureSeule
                          ? 'Consultation seule : votre profil ne peut pas '
                                'publier dans ce module.'
                          : 'Annoncer à un public, notifier une personne, et '
                                'savoir ce qui est réellement parti.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onRecharger,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Indicateur(
                libelle: 'Annonces',
                valeur: annonces == null ? '—' : '${annonces.length}',
              ),
              Indicateur(
                libelle: 'Notifications',
                valeur: notifications == null ? '—' : '${notifications.length}',
              ),
              // Le chiffre qu'on cherche quand une famille dit n'avoir rien
              // reçu: ce qui est écrit et n'est pas encore parti.
              Indicateur(
                libelle: 'En attente d\'envoi',
                valeur: enAttente == null ? '—' : '$enAttente',
                couleur: (enAttente ?? 0) > 0
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
