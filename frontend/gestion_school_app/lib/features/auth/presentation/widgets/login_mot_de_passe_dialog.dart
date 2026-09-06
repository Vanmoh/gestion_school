/// Mot de passe oublie: la marche a suivre, pas un formulaire.
///
/// Le serveur n'offre aucun libre-service. La seule reinitialisation existante
/// est `POST /api/auth/users/<id>/reset-password/`, reservee a
/// l'administration (« L'administration fixe un mot de passe provisoire,
/// qu'elle communique »), et aucun envoi de courriel n'est configure. Un champ
/// « votre adresse e-mail » suivi d'un bouton « Envoyer » serait donc un
/// mensonge d'interface: l'utilisateur attendrait un message qui ne partirait
/// jamais.
///
/// C'est exactement la reponse que le portail donne deja a « Demander un
/// acces »: meme probleme, meme forme, meme widget de contact.
library;

import 'package:flutter/material.dart';

import '../../../../models/etablissement.dart';
import '../../../../widgets/etablissement_identity.dart';

class LoginMotDePasseOublieDialog extends StatelessWidget {
  final Etablissement etablissement;

  /// Coordonnees retenues, deja resolues par l'appelant (etablissement, puis
  /// personnalisation, puis constantes livrees).
  final String? telephone;
  final String? email;

  const LoginMotDePasseOublieDialog({
    super.key,
    required this.etablissement,
    this.telephone,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aDesCoordonnees =
        (telephone != null && telephone!.isNotEmpty) ||
        (email != null && email!.isNotEmpty);

    return AlertDialog(
      icon: const Icon(Icons.key_off_outlined),
      title: const Text('Mot de passe oublié'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'L\'application ne réinitialise pas les mots de passe. Seule '
                'l\'administration de l\'établissement peut en fixer un '
                'nouveau, provisoire, qu\'elle vous communique.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Contactez-la en précisant votre nom d\'utilisateur.',
                style: theme.textTheme.bodyMedium,
              ),
              if (aDesCoordonnees) ...[
                const EtabSectionLabel('Contact'),
                EtabContactLine(
                  icon: Icons.apartment_rounded,
                  value: etabDisplayName(etablissement),
                ),
                if (telephone != null && telephone!.isNotEmpty)
                  EtabContactLine(icon: Icons.call_outlined, value: telephone!),
                if (email != null && email!.isNotEmpty)
                  EtabContactLine(
                    icon: Icons.mail_outline_rounded,
                    value: email!,
                  ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'Aucune coordonnée n\'est enregistrée pour cet '
                  'établissement : rapprochez-vous du secrétariat.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}
