import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/barre_recherche_module.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../domain/communication_models.dart';
import 'communication_controller.dart';

/// Les annonces de l'école, et le public auquel chacune s'adresse.
///
/// Le public n'était pas choisi mais tapé — « Audience (all, parents,
/// teachers...) » — et le serveur ne s'en servait pas: une consigne écrite
/// « teachers » s'affichait chez les familles. Il se choisit maintenant dans
/// une liste fermée, et chaque carte le porte en clair: on voit à qui on parle
/// sans ouvrir l'annonce.
class OngletAnnonces extends ConsumerStatefulWidget {
  const OngletAnnonces({super.key});

  @override
  ConsumerState<OngletAnnonces> createState() => _OngletAnnoncesState();
}

class _OngletAnnoncesState extends ConsumerState<OngletAnnonces> {
  final _recherche = TextEditingController();
  final _titre = TextEditingController();
  final _message = TextEditingController();

  PublicDeLAnnonce _public = PublicDeLAnnonce.tous;
  FiltreDesAnnonces _filtre = FiltreDesAnnonces.aucun;

  /// La rédaction reste pliée jusqu'à ce qu'on en ait besoin.
  ///
  /// Le formulaire occupait le haut de la page en permanence, y compris pour
  /// un profil en lecture seule, où ses champs étaient grisés sans rien dire.
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

  Future<void> _publier() async {
    final titre = _titre.text.trim();
    final message = _message.text.trim();
    if (titre.isEmpty || message.isEmpty) {
      _dire('Un titre et un message sont nécessaires.', erreur: true);
      return;
    }

    await ref
        .read(communicationMutationProvider.notifier)
        .publierUneAnnonce(titre: titre, message: message, public: _public);

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Publication refusée.', erreur: true);
      return;
    }

    _titre.clear();
    _message.clear();
    setState(() => _redactionOuverte = false);
    _dire('Annonce publiée pour ${_public.libelle}.', succes: true);
  }

  Future<void> _changerLePublic(AnnonceItem annonce, PublicDeLAnnonce vers) async {
    await ref
        .read(communicationMutationProvider.notifier)
        .corrigerUneAnnonce(id: annonce.id, public: vers);

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Changement refusé.', erreur: true);
    } else {
      _dire('Annonce désormais adressée à ${vers.libelle}.', succes: true);
    }
  }

  Future<void> _retirer(AnnonceItem annonce) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Retirer cette annonce'),
        content: Text(
          '« ${annonce.titre} » ne sera plus lisible par '
          '${annonce.public.libelle.toLowerCase()}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirmer-retrait-annonce'),
            onPressed: () => Navigator.of(contexte).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    await ref
        .read(communicationMutationProvider.notifier)
        .retirerUneAnnonce(annonce.id);

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Retrait refusé.', erreur: true);
    } else {
      _dire('Annonce retirée.', succes: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final peutEcrire = droits.canWrite('communication');
    final peutSupprimer = droits.canDelete('communication');
    final annoncesAsync = ref.watch(annoncesProvider(_filtre));
    final mutation = ref.watch(communicationMutationProvider);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        BarreRechercheModule(
          controller: _recherche,
          indication: 'Rechercher dans les annonces (titre, message)',
          onChanged: (valeur) =>
              setState(() => _filtre = _filtre.avec(recherche: valeur)),
          onEffacer: () => setState(
            () => _filtre = _filtre.avec(recherche: ''),
          ),
          rechercheEnCours: annoncesAsync.isLoading,
          actions: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<PublicDeLAnnonce?>(
                key: const Key('filtre-public'),
                isExpanded: true,
                isDense: true,
                initialValue: _filtre.public,
                decoration: const InputDecoration(
                  labelText: 'Public',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous les publics')),
                  for (final public in PublicDeLAnnonce.values)
                    DropdownMenuItem(value: public, child: Text(public.libelle)),
                ],
                onChanged: (valeur) => setState(() {
                  _filtre = valeur == null
                      ? _filtre.avec(viderPublic: true)
                      : _filtre.avec(public: valeur);
                }),
              ),
            ),
            if (peutEcrire)
              FilledButton.icon(
                key: const Key('basculer-redaction-annonce'),
                onPressed: () =>
                    setState(() => _redactionOuverte = !_redactionOuverte),
                icon: Icon(
                  _redactionOuverte ? Icons.close : Icons.campaign_outlined,
                ),
                label: Text(_redactionOuverte ? 'Fermer' : 'Nouvelle annonce'),
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
                  Text('Nouvelle annonce', style: textTheme.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('annonce-titre'),
                    controller: _titre,
                    decoration: const InputDecoration(labelText: 'Titre'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('annonce-message'),
                    controller: _message,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<PublicDeLAnnonce>(
                    key: const Key('annonce-public'),
                    isExpanded: true,
                    initialValue: _public,
                    decoration: const InputDecoration(
                      labelText: 'Qui doit la lire',
                      helperText:
                          'Seul ce public verra l\'annonce dans son écran.',
                    ),
                    items: [
                      for (final public in PublicDeLAnnonce.values)
                        DropdownMenuItem(
                          value: public,
                          child: Text(public.libelle),
                        ),
                    ],
                    onChanged: (valeur) => setState(
                      () => _public = valeur ?? PublicDeLAnnonce.tous,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('publier-annonce'),
                    onPressed: mutation.isLoading ? null : _publier,
                    child: const Text('Publier'),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),

        annoncesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (erreur, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Les annonces n\'ont pas pu être chargées.',
                style: textTheme.bodyMedium,
              ),
            ),
          ),
          data: (annonces) {
            if (annonces.isEmpty) {
              return EtatVideRecherche(
                recherche: _filtre.recherche,
                invitation: 'Aucune annonce publiée.',
                precision: 'Aucune annonce ne correspond',
                motAucun: 'annonce',
              );
            }
            return Column(
              children: [
                for (final annonce in annonces)
                  _CarteDAnnonce(
                    annonce: annonce,
                    peutEcrire: peutEcrire,
                    peutSupprimer: peutSupprimer,
                    occupe: mutation.isLoading,
                    onChangerLePublic: (vers) => _changerLePublic(annonce, vers),
                    onRetirer: () => _retirer(annonce),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CarteDAnnonce extends StatelessWidget {
  final AnnonceItem annonce;
  final bool peutEcrire;
  final bool peutSupprimer;
  final bool occupe;
  final ValueChanged<PublicDeLAnnonce> onChangerLePublic;
  final VoidCallback onRetirer;

  const _CarteDAnnonce({
    required this.annonce,
    required this.peutEcrire,
    required this.peutSupprimer,
    required this.occupe,
    required this.onChangerLePublic,
    required this.onRetirer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: ValueKey('annonce-${annonce.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(annonce.titre, style: textTheme.titleMedium),
                ),
                // Le public en tête de carte: c'est la première chose à
                // vérifier avant de laisser une annonce en ligne.
                Chip(
                  label: Text(annonce.public.libelle),
                  avatar: Icon(
                    annonce.public == PublicDeLAnnonce.tous
                        ? Icons.public
                        : Icons.group_outlined,
                    size: 16,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                if (peutEcrire)
                  PopupMenuButton<PublicDeLAnnonce>(
                    key: ValueKey('changer-public-${annonce.id}'),
                    tooltip: 'Changer de public',
                    icon: const Icon(Icons.tune, size: 18),
                    enabled: !occupe,
                    onSelected: onChangerLePublic,
                    itemBuilder: (_) => [
                      for (final public in PublicDeLAnnonce.values)
                        PopupMenuItem(
                          value: public,
                          enabled: public != annonce.public,
                          child: Text(public.libelle),
                        ),
                    ],
                  ),
                if (peutSupprimer)
                  IconButton(
                    key: ValueKey('retirer-annonce-${annonce.id}'),
                    tooltip: 'Retirer',
                    onPressed: occupe ? null : onRetirer,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(annonce.message, style: textTheme.bodyMedium),
            if (annonce.publieeLe.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Publiée le ${annonce.publieeLe.split('T').first}',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
