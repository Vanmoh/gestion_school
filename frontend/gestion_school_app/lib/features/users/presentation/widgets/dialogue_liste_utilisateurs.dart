import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/user_account.dart';
import '../users_controller.dart';
import 'pastille_compte.dart';

/// L'annuaire complet des comptes, page par page.
///
/// La page principale s'ouvre desormais sur une recherche, comme les modules
/// eleve et enseignant: on y vient avec un nom en tete. Parcourir tous les
/// comptes d'un etablissement reste pourtant un usage courant -- pour reperer
/// les acces restes ouverts, par exemple -- et cette liste-la lui est reservee
/// plutot que d'occuper l'ecran en permanence.
///
/// Elle porte sa propre pagination: la faire piloter par la page hote
/// obligerait celle-ci a garder un etat qu'elle n'affiche plus.
class DialogueListeUtilisateurs extends ConsumerStatefulWidget {
  /// Rôle preselectionne, repris du filtre de la page hote: on arrive dans la
  /// liste avec le meme cadrage qu'on avait a l'ecran.
  final String roleFiltre;

  /// Etat preselectionne: 'all', 'actifs' ou 'desactives'.
  final String etatFiltre;

  /// Libelle lisible d'un role technique, fourni par la page hote qui porte
  /// deja la table de correspondance.
  final String Function(String role) libelleRole;

  const DialogueListeUtilisateurs({
    super.key,
    this.roleFiltre = 'all',
    this.etatFiltre = 'all',
    required this.libelleRole,
  });

  /// Ouvre la liste et rend le compte choisi, ou null si on a seulement
  /// regarde.
  static Future<UserAccount?> ouvrir(
    BuildContext context, {
    String roleFiltre = 'all',
    String etatFiltre = 'all',
    required String Function(String role) libelleRole,
  }) {
    return showDialog<UserAccount>(
      context: context,
      builder: (_) => DialogueListeUtilisateurs(
        roleFiltre: roleFiltre,
        etatFiltre: etatFiltre,
        libelleRole: libelleRole,
      ),
    );
  }

  @override
  ConsumerState<DialogueListeUtilisateurs> createState() =>
      _DialogueListeUtilisateursState();
}

class _DialogueListeUtilisateursState
    extends ConsumerState<DialogueListeUtilisateurs> {
  static const _taillePage = 25;

  final _rechercheController = TextEditingController();
  Timer? _attente;

  int _page = 1;
  String _recherche = '';
  late final String _role = widget.roleFiltre;
  late final String _etat = widget.etatFiltre;

  @override
  void dispose() {
    _attente?.cancel();
    _rechercheController.dispose();
    super.dispose();
  }

  void _surFrappe(String valeur) {
    _attente?.cancel();
    // Une requete par caractere saturerait le serveur pour un resultat que
    // la frappe suivante remplace aussitot.
    _attente = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _recherche = valeur.trim();
        _page = 1;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final query = UsersPageQuery(
      page: _page,
      pageSize: _taillePage,
      search: _recherche,
      role: _role == 'all' ? null : _role,
      actif: switch (_etat) {
        'actifs' => true,
        'desactives' => false,
        _ => null,
      },
    );
    final pageAsync = ref.watch(usersPaginatedProvider(query));

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.groups_2_outlined, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Liste des utilisateurs',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: TextField(
                controller: _rechercheController,
                onChanged: _surFrappe,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filtrer la liste : nom, identifiant, e-mail…',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _rechercheController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _attente?.cancel();
                            _rechercheController.clear();
                            setState(() {
                              _recherche = '';
                              _page = 1;
                            });
                          },
                        ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: pageAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'La liste n\'a pas pu être chargée.',
                          style: textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text('$error', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () =>
                              ref.invalidate(usersPaginatedProvider(query)),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (page) {
                  if (page.results.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _recherche.isEmpty
                              ? 'Aucun compte pour ces filtres.'
                              : 'Aucun compte ne correspond à « $_recherche ».',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    itemCount: page.results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final compte = page.results[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: CircleAvatar(
                          child: Text(_initiales(compte)),
                        ),
                        title: Text(
                          compte.fullName.trim().isEmpty
                              ? compte.username
                              : compte.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${compte.username} · ${widget.libelleRole(compte.role)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PastilleCompte(compte: compte),
                        // Choisir un compte referme la liste et ouvre sa
                        // palette: on est venu la pour agir sur quelqu'un.
                        onTap: () => Navigator.of(context).pop(compte),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: pageAsync.maybeWhen(
                data: (page) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Page $_page · ${page.results.length} sur ${page.count} compte'
                        '${page.count > 1 ? 's' : ''}',
                        style: textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Page précédente',
                      onPressed: page.hasPrevious
                          ? () => setState(() => _page -= 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'Page suivante',
                      onPressed: page.hasNext
                          ? () => setState(() => _page += 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                orElse: () => const SizedBox(height: 40),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initiales(UserAccount compte) {
    final source = compte.fullName.trim().isEmpty
        ? compte.username
        : compte.fullName;
    final mots = source
        .trim()
        .split(RegExp(r'\s+'))
        .where((mot) => mot.isNotEmpty)
        .toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) {
      final mot = mots.first;
      return (mot.length == 1 ? mot : mot.substring(0, 2)).toUpperCase();
    }
    return '${mots.first[0]}${mots[1][0]}'.toUpperCase();
  }
}
