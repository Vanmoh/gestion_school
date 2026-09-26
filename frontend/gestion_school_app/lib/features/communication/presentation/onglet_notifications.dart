import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/barre_recherche_module.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../domain/communication_models.dart';
import 'communication_controller.dart';

/// La file d'envoi: ce qui est parti, et surtout ce qui ne l'est pas.
///
/// L'écran listait les notifications sans distinguer les deux, alors qu'une
/// notification créée n'est expédiée qu'au passage suivant de la tâche
/// d'envoi — et reste en attente indéfiniment si le canal est fermé, par
/// exemple une passerelle SMS inactive. « Ce qui attend encore » passe donc
/// en tête, comme les épreuves sans surveillant dans le module Examens.
class OngletNotifications extends ConsumerStatefulWidget {
  const OngletNotifications({super.key});

  @override
  ConsumerState<OngletNotifications> createState() =>
      _OngletNotificationsState();
}

class _OngletNotificationsState extends ConsumerState<OngletNotifications> {
  final _recherche = TextEditingController();
  final _titre = TextEditingController();
  final _message = TextEditingController();

  CanalDeNotification _canal = CanalDeNotification.push;
  int? _destinataireId;
  FiltreDesNotifications _filtre = FiltreDesNotifications.aucun;
  bool _redactionOuverte = false;

  @override
  void dispose() {
    _recherche.dispose();
    _titre.dispose();
    _message.dispose();
    super.dispose();
  }

  void _dire(String message, {bool succes = false, bool erreur = false}) {
    if (!mounted) return;
    ForegroundNotice.show(context, message, isSuccess: succes, isError: erreur);
  }

  Future<void> _creer() async {
    final titre = _titre.text.trim();
    final message = _message.text.trim();
    if (titre.isEmpty || message.isEmpty) {
      _dire('Un titre et un message sont nécessaires.', erreur: true);
      return;
    }

    await ref
        .read(communicationMutationProvider.notifier)
        .creerUneNotification(
          titre: titre,
          message: message,
          canal: _canal,
          destinataireId: _destinataireId,
        );

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Création refusée.', erreur: true);
      return;
    }

    _titre.clear();
    _message.clear();
    setState(() => _redactionOuverte = false);
    // Le mot juste: rien n'est parti à cet instant, la tâche d'envoi s'en
    // charge. Dire « envoyée » ferait croire l'inverse.
    _dire('Notification mise en file d\'envoi.', succes: true);
  }

  Future<void> _retirer(NotificationItem notification) async {
    await ref
        .read(communicationMutationProvider.notifier)
        .retirerUneNotification(notification.id);

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Retrait refusé.', erreur: true);
    } else {
      _dire('Notification retirée.', succes: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final peutEcrire = droits.canWrite('communication');
    final peutSupprimer = droits.canDelete('communication');
    final notificationsAsync = ref.watch(notificationsProvider(_filtre));
    final destinatairesAsync = ref.watch(destinatairesProvider);
    final mutation = ref.watch(communicationMutationProvider);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        BarreRechercheModule(
          controller: _recherche,
          indication: 'Rechercher (titre, message, destinataire)',
          onChanged: (valeur) =>
              setState(() => _filtre = _filtre.avec(recherche: valeur)),
          onEffacer: () =>
              setState(() => _filtre = _filtre.avec(recherche: '')),
          rechercheEnCours: notificationsAsync.isLoading,
          actions: [
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<CanalDeNotification?>(
                key: const Key('filtre-canal'),
                isExpanded: true,
                isDense: true,
                initialValue: _filtre.canal,
                decoration: const InputDecoration(
                  labelText: 'Canal',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous')),
                  for (final canal in CanalDeNotification.values)
                    DropdownMenuItem(value: canal, child: Text(canal.libelle)),
                ],
                onChanged: (valeur) => setState(() {
                  _filtre = valeur == null
                      ? _filtre.avec(viderCanal: true)
                      : _filtre.avec(canal: valeur);
                }),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<bool?>(
                key: const Key('filtre-envoi'),
                isExpanded: true,
                isDense: true,
                initialValue: _filtre.envoyees,
                decoration: const InputDecoration(
                  labelText: 'État',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tous les états')),
                  DropdownMenuItem(value: false, child: Text('En attente')),
                  DropdownMenuItem(value: true, child: Text('Parties')),
                ],
                onChanged: (valeur) => setState(() {
                  _filtre = valeur == null
                      ? _filtre.avec(viderEnvoi: true)
                      : _filtre.avec(envoyees: valeur);
                }),
              ),
            ),
            if (peutEcrire)
              FilledButton.icon(
                key: const Key('basculer-redaction-notification'),
                onPressed: () =>
                    setState(() => _redactionOuverte = !_redactionOuverte),
                icon: Icon(
                  _redactionOuverte
                      ? Icons.close
                      : Icons.notifications_active_outlined,
                ),
                label: Text(
                  _redactionOuverte ? 'Fermer' : 'Nouvelle notification',
                ),
              ),
          ],
        ),

        if (_redactionOuverte && peutEcrire) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Nouvelle notification', style: textTheme.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('notification-titre'),
                    controller: _titre,
                    decoration: const InputDecoration(labelText: 'Titre'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('notification-message'),
                    controller: _message,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<CanalDeNotification>(
                    key: const Key('notification-canal'),
                    isExpanded: true,
                    initialValue: _canal,
                    decoration: const InputDecoration(labelText: 'Canal'),
                    items: [
                      for (final canal in CanalDeNotification.values)
                        DropdownMenuItem(
                          value: canal,
                          child: Text(canal.libelle),
                        ),
                    ],
                    onChanged: (valeur) => setState(
                      () => _canal = valeur ?? CanalDeNotification.push,
                    ),
                  ),
                  const SizedBox(height: 10),
                  destinatairesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('Annuaire indisponible'),
                    data: (destinataires) =>
                        DropdownButtonFormField<int?>(
                          key: const Key('notification-destinataire'),
                          isExpanded: true,
                          initialValue: _destinataireId,
                          decoration: const InputDecoration(
                            labelText: 'Destinataire',
                            helperText:
                                'Sans destinataire, la notification vaut pour '
                                'tout l\'établissement.',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Tout l\'établissement'),
                            ),
                            for (final personne in destinataires)
                              DropdownMenuItem(
                                value: personne.id,
                                child: Text(personne.libelle),
                              ),
                          ],
                          onChanged: (valeur) =>
                              setState(() => _destinataireId = valeur),
                        ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('creer-notification'),
                    onPressed: mutation.isLoading ? null : _creer,
                    child: const Text('Mettre en file d\'envoi'),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        notificationsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (erreur, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'La file d\'envoi n\'a pas pu être chargée.',
                style: textTheme.bodyMedium,
              ),
            ),
          ),
          data: (notifications) {
            if (notifications.isEmpty) {
              return EtatVideRecherche(
                recherche: _filtre.recherche,
                invitation: 'Aucune notification.',
                precision: 'Aucune notification ne correspond',
                motAucun: 'notification',
              );
            }

            final enAttente =
                notifications.where((ligne) => !ligne.envoyee).toList();
            final parties =
                notifications.where((ligne) => ligne.envoyee).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (enAttente.isNotEmpty) ...[
                  Text('En attente d\'envoi', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final ligne in enAttente)
                    _Ligne(
                      notification: ligne,
                      peutSupprimer: peutSupprimer,
                      occupe: mutation.isLoading,
                      onRetirer: () => _retirer(ligne),
                    ),
                  const SizedBox(height: 18),
                ],
                if (parties.isNotEmpty) ...[
                  Text('Parties', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final ligne in parties)
                    _Ligne(
                      notification: ligne,
                      peutSupprimer: peutSupprimer,
                      occupe: mutation.isLoading,
                      onRetirer: () => _retirer(ligne),
                    ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  final NotificationItem notification;
  final bool peutSupprimer;
  final bool occupe;
  final VoidCallback onRetirer;

  const _Ligne({
    required this.notification,
    required this.peutSupprimer,
    required this.occupe,
    required this.onRetirer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      key: ValueKey('notification-${notification.id}'),
      child: ListTile(
        leading: Icon(
          notification.envoyee
              ? Icons.check_circle_outline
              : Icons.schedule_outlined,
          color: notification.envoyee ? null : scheme.error,
        ),
        title: Text(notification.titre),
        // Le destinataire vient du serveur: l'écran le résolvait sur
        // l'annuaire qu'il gardait en mémoire, et affichait « Global » dès
        // que la personne en était absente.
        subtitle: Text(
          '${notification.canal.libelle} • '
          '${notification.estGlobale ? 'Tout l\'établissement' : notification.destinataire}'
          '${notification.envoyee && notification.envoyeeLe.isNotEmpty ? ' • parti le ${notification.envoyeeLe.split('T').first}' : ''}',
        ),
        trailing: peutSupprimer
            ? IconButton(
                key: ValueKey('retirer-notification-${notification.id}'),
                tooltip: 'Retirer',
                onPressed: occupe ? null : onRetirer,
                icon: const Icon(Icons.delete_outline, size: 20),
              )
            : null,
      ),
    );
  }
}
