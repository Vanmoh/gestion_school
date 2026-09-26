import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../domain/communication_models.dart';
import 'communication_controller.dart';

/// La passerelle par laquelle les SMS quittent l'école.
///
/// Onglet à part, et non section de la page: l'objet porte le jeton d'API du
/// fournisseur, et la clé de droits `sms_config` n'est ouverte qu'à la
/// direction — c'est pourquoi elle est séparée de `communication` dans la
/// matrice.
///
/// Deux choses que cet onglet dit et que l'ancien écran taisait: **une
/// passerelle inactive retient les SMS en file** plutôt que de les perdre, et
/// **couper un canal ne demande pas de supprimer sa configuration** — la
/// suppression était la seule écriture proposée, et le jeton partait avec.
class OngletPasserelleSms extends ConsumerStatefulWidget {
  const OngletPasserelleSms({super.key});

  @override
  ConsumerState<OngletPasserelleSms> createState() =>
      _OngletPasserelleSmsState();
}

class _OngletPasserelleSmsState extends ConsumerState<OngletPasserelleSms> {
  final _fournisseur = TextEditingController();
  final _url = TextEditingController();
  final _jeton = TextEditingController();
  final _expediteur = TextEditingController();
  bool _active = true;
  bool _formulaireOuvert = false;

  @override
  void dispose() {
    _fournisseur.dispose();
    _url.dispose();
    _jeton.dispose();
    _expediteur.dispose();
    super.dispose();
  }

  void _dire(String message, {bool succes = false, bool erreur = false}) {
    if (!mounted) return;
    ForegroundNotice.show(context, message, isSuccess: succes, isError: erreur);
  }

  Future<void> _enregistrer() async {
    final fournisseur = _fournisseur.text.trim();
    final url = _url.text.trim();
    final jeton = _jeton.text.trim();
    if (fournisseur.isEmpty || url.isEmpty || jeton.isEmpty) {
      _dire(
        'Le fournisseur, l\'adresse de l\'API et le jeton sont nécessaires.',
        erreur: true,
      );
      return;
    }

    await ref
        .read(communicationMutationProvider.notifier)
        .enregistrerUnePasserelle(
          fournisseur: fournisseur,
          urlApi: url,
          jeton: jeton,
          expediteur: _expediteur.text.trim(),
          active: _active,
        );

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Enregistrement refusé.', erreur: true);
      return;
    }

    _fournisseur.clear();
    _url.clear();
    _jeton.clear();
    _expediteur.clear();
    setState(() => _formulaireOuvert = false);
    _dire('Passerelle enregistrée.', succes: true);
  }

  Future<void> _basculer(PasserelleSmsItem passerelle) async {
    await ref
        .read(communicationMutationProvider.notifier)
        .basculerUnePasserelle(id: passerelle.id, active: !passerelle.active);

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Changement refusé.', erreur: true);
    } else {
      _dire(
        passerelle.active
            ? 'Canal coupé. Les SMS restent en file jusqu\'à sa réouverture.'
            : 'Canal ouvert.',
        succes: true,
      );
    }
  }

  Future<void> _supprimer(PasserelleSmsItem passerelle) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Supprimer cette passerelle'),
        content: Text(
          'Le jeton d\'API de ${passerelle.fournisseur} sera perdu et devra '
          'être redemandé au fournisseur. Pour seulement couper le canal, '
          'désactivez-la.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirmer-suppression-passerelle'),
            onPressed: () => Navigator.of(contexte).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    await ref
        .read(communicationMutationProvider.notifier)
        .retirerUnePasserelle(passerelle.id);

    if (ref.read(communicationMutationProvider).hasError) {
      _dire('Suppression refusée.', erreur: true);
    } else {
      _dire('Passerelle supprimée.', succes: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peutEcrire = ref.watch(currentPermissionsProvider).canWrite('sms_config');
    final passerellesAsync = ref.watch(passerellesSmsProvider);
    final mutation = ref.watch(communicationMutationProvider);
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Passerelle SMS',
                style: textTheme.titleMedium,
              ),
            ),
            if (peutEcrire)
              FilledButton.icon(
                key: const Key('basculer-formulaire-passerelle'),
                onPressed: () =>
                    setState(() => _formulaireOuvert = !_formulaireOuvert),
                icon: Icon(_formulaireOuvert ? Icons.close : Icons.add),
                label: Text(_formulaireOuvert ? 'Fermer' : 'Ajouter'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Sans passerelle active, les notifications SMS restent en file '
          'd\'envoi: elles ne sont pas perdues, elles attendent.',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),

        if (_formulaireOuvert && peutEcrire) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('passerelle-fournisseur'),
                    controller: _fournisseur,
                    decoration: const InputDecoration(
                      labelText: 'Fournisseur',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('passerelle-url'),
                    controller: _url,
                    decoration: const InputDecoration(
                      labelText: 'Adresse de l\'API',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('passerelle-jeton'),
                    controller: _jeton,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Jeton d\'API',
                      helperText:
                          'Conservé côté serveur; il ne se relit pas ici.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('passerelle-expediteur'),
                    controller: _expediteur,
                    decoration: const InputDecoration(
                      labelText: 'Expéditeur affiché (facultatif)',
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    key: const Key('passerelle-active'),
                    contentPadding: EdgeInsets.zero,
                    value: _active,
                    title: const Text('Ouvrir le canal immédiatement'),
                    onChanged: (valeur) => setState(() => _active = valeur),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('enregistrer-passerelle'),
                    onPressed: mutation.isLoading ? null : _enregistrer,
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),

        passerellesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (erreur, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'La configuration n\'a pas pu être chargée.',
                style: textTheme.bodyMedium,
              ),
            ),
          ),
          data: (passerelles) {
            if (passerelles.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 32,
                    horizontal: 20,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sms_outlined, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Aucune passerelle configurée: le canal SMS est '
                          'fermé.',
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final passerelle in passerelles)
                  Card(
                    key: ValueKey('passerelle-${passerelle.id}'),
                    child: ListTile(
                      leading: Icon(
                        passerelle.active
                            ? Icons.cell_tower
                            : Icons.signal_cellular_off_outlined,
                        color: passerelle.active ? null : scheme.error,
                      ),
                      title: Text(passerelle.fournisseur),
                      subtitle: Text(
                        '${passerelle.urlApi}'
                        '${passerelle.expediteur.isEmpty ? '' : ' • expéditeur ${passerelle.expediteur}'}',
                      ),
                      trailing: !peutEcrire
                          ? Text(passerelle.active ? 'Ouvert' : 'Coupé')
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  key: ValueKey(
                                    'basculer-passerelle-${passerelle.id}',
                                  ),
                                  onPressed: mutation.isLoading
                                      ? null
                                      : () => _basculer(passerelle),
                                  child: Text(
                                    passerelle.active ? 'Couper' : 'Ouvrir',
                                  ),
                                ),
                                IconButton(
                                  key: ValueKey(
                                    'supprimer-passerelle-${passerelle.id}',
                                  ),
                                  tooltip: 'Supprimer',
                                  onPressed: mutation.isLoading
                                      ? null
                                      : () => _supprimer(passerelle),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
