part of 'students_page.dart';

/// Ce qu'on remet à la famille, une fois l'inscription faite.
///
/// Le mot de passe n'existe en clair qu'à cet instant: le serveur le hache
/// dès qu'il le pose, et il ne repassera jamais. S'il n'est pas noté ici, il
/// faudra le réinitialiser — d'où la fenêtre qui s'impose et le bouton qui
/// copie tout d'un coup.
extension _IdentifiantsRemis on _StudentsPageState {
  Future<void> _montrerLesIdentifiants(ResultatInscription resultat) async {
    final lignes = <String>[
      'Élève : ${resultat.eleve.fullName}',
      'Identifiant : ${resultat.identifiantsEleve.username}',
      'Mot de passe : ${resultat.identifiantsEleve.motDePasse}',
      if (resultat.identifiantsParent != null) ...[
        '',
        'Parent : ${resultat.parentNom}',
        'Identifiant : ${resultat.identifiantsParent!.username}',
        'Mot de passe : ${resultat.identifiantsParent!.motDePasse}',
      ],
    ];

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (contexte) {
        final scheme = Theme.of(contexte).colorScheme;
        return AlertDialog(
          title: const Text('Inscription enregistrée'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Notez ces accès et remettez-les à la famille : '
                  'ils ne s\'afficheront plus.',
                  style: Theme.of(contexte).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                _blocAcces(
                  contexte,
                  titre: 'Élève — ${resultat.eleve.fullName}',
                  identifiants: resultat.identifiantsEleve,
                ),
                if (resultat.identifiantsParent != null) ...[
                  const SizedBox(height: 12),
                  _blocAcces(
                    contexte,
                    titre: 'Parent — ${resultat.parentNom}',
                    identifiants: resultat.identifiantsParent!,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    // Le parent existait déjà: il garde le mot de passe
                    // qu'il a choisi, et l'écraser lui ferait perdre l'accès
                    // à ses autres enfants.
                    '${resultat.parentNom} était déjà enregistré : '
                    'l\'élève a rejoint son compte, qui garde ses accès.',
                    style: Theme.of(contexte).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 15, color: scheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'À la première connexion, chacun devra choisir son '
                        'propre mot de passe.',
                        style: Theme.of(contexte).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: lignes.join('\n')),
                );
                if (contexte.mounted) {
                  ScaffoldMessenger.of(contexte).showSnackBar(
                    const SnackBar(content: Text('Accès copiés.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Copier'),
            ),
            FilledButton(
              key: const Key('identifiants-fermer'),
              onPressed: () => Navigator.of(contexte).pop(),
              child: const Text('J\'ai noté'),
            ),
          ],
        );
      },
    );
  }

  Widget _blocAcces(
    BuildContext contexte, {
    required String titre,
    required IdentifiantsRemis identifiants,
  }) {
    final scheme = Theme.of(contexte).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre, style: Theme.of(contexte).textTheme.labelLarge),
          const SizedBox(height: 6),
          SelectableText(
            'Identifiant : ${identifiants.username}',
            style: Theme.of(contexte).textTheme.bodyMedium,
          ),
          SelectableText(
            'Mot de passe : ${identifiants.motDePasse}',
            style: Theme.of(contexte).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
