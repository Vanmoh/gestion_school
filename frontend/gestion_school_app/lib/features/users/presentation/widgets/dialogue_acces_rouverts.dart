import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/acces_rouverts.dart';

/// Les accès rendus à une classe, à noter avant de fermer.
///
/// Les mots de passe n'existent en clair qu'ici: le serveur les hache dès
/// qu'il les pose, et ils ne repasseront jamais. D'où la fenêtre qui
/// s'impose et le bouton qui copie tout d'un coup — c'est la même règle que
/// pour les identifiants remis après une inscription.
class DialogueAccesRouverts extends StatelessWidget {
  final AccesRouverts acces;
  final String classe;

  const DialogueAccesRouverts({
    super.key,
    required this.acces,
    required this.classe,
  });

  /// Le texte que le secrétariat copie, colle et imprime.
  String get texte {
    final lignes = <String>['Accès rouverts — $classe', ''];
    for (final famille in acces.comptes) {
      lignes.add('${famille.eleve} (${famille.matricule})');
      if (famille.motDePasse.isNotEmpty) {
        lignes.add('  Élève : ${famille.identifiant} / ${famille.motDePasse}');
      }
      if (famille.porteUnParent) {
        lignes.add(
          '  Parent ${famille.parent} : '
          '${famille.parentIdentifiant} / ${famille.parentMotDePasse}',
        );
      }
      lignes.add('');
    }
    return lignes.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: Text('Accès rouverts — $classe'),
      content: SizedBox(
        width: 520,
        child: acces.estVide
            ? Text(
                // Ce n'est pas un échec: c'est la bonne nouvelle que tout le
                // monde entre déjà.
                acces.dejaUtilises > 0
                    ? 'Rien à rouvrir : les ${acces.dejaUtilises} comptes de '
                          'cette classe servent déjà.'
                    : 'Aucun compte à rouvrir dans cette classe.',
                style: theme.textTheme.bodyMedium,
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Notez ces accès et remettez-les aux familles : ils ne '
                      's\'afficheront plus. Chacune devra choisir son propre '
                      'mot de passe à la première connexion.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (acces.dejaUtilises > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${acces.dejaUtilises} compte(s) de cette classe '
                        'servent déjà : ils n\'ont pas été touchés.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    for (final famille in acces.comptes)
                      _LigneFamille(famille: famille),
                  ],
                ),
              ),
      ),
      actions: [
        if (!acces.estVide)
          OutlinedButton.icon(
            key: const Key('copier-les-acces'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texte));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Accès copiés.')),
              );
            },
            icon: const Icon(Icons.content_copy_outlined, size: 18),
            label: const Text('Tout copier'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('J\'ai noté'),
        ),
      ],
    );
  }
}

class _LigneFamille extends StatelessWidget {
  final AccesDUneFamille famille;

  const _LigneFamille({required this.famille});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${famille.eleve} — ${famille.matricule}',
            style: theme.textTheme.titleSmall,
          ),
          if (famille.motDePasse.isNotEmpty)
            SelectableText(
              'Élève : ${famille.identifiant}  ·  ${famille.motDePasse}',
              style: theme.textTheme.bodyMedium,
            )
          else
            Text(
              // Dire pourquoi cette ligne n'a pas de mot de passe élève:
              // sinon elle passe pour une ligne incomplète.
              'Élève : son compte sert déjà, il garde son mot de passe.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          if (famille.porteUnParent)
            SelectableText(
              'Parent ${famille.parent} : '
              '${famille.parentIdentifiant}  ·  ${famille.parentMotDePasse}',
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
