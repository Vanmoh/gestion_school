import 'package:flutter/material.dart';

import '../../domain/user_account.dart';

/// L'administration fixe un mot de passe provisoire, qu'elle communique.
///
/// L'écran offrait un champ « Mot de passe » à la modification, et l'API le
/// recevait sans rien en faire: elle répondait 200 et le mot de passe ne
/// changeait pas. Personne ne pouvait dépanner un compte dont le mot de
/// passe était perdu.
class DialogueReinitialisation extends StatefulWidget {
  final UserAccount compte;

  const DialogueReinitialisation({super.key, required this.compte});

  @override
  State<DialogueReinitialisation> createState() =>
      _DialogueReinitialisationState();
}

class _DialogueReinitialisationState extends State<DialogueReinitialisation> {
  final _controleur = TextEditingController();
  bool _visible = false;
  String? _erreur;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _valider() {
    final saisi = _controleur.text;
    if (saisi.length < 8) {
      setState(
        () => _erreur = 'Le mot de passe provisoire doit faire 8 caractères '
            'au moins.',
      );
      return;
    }
    Navigator.of(context).pop(saisi);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Réinitialiser le mot de passe'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compte : ${widget.compte.fullName} (${widget.compte.username})',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('mot-de-passe-provisoire'),
              controller: _controleur,
              autofocus: true,
              obscureText: !_visible,
              decoration: InputDecoration(
                labelText: 'Mot de passe provisoire',
                helperText: '8 caractères minimum',
                suffixIcon: IconButton(
                  tooltip: _visible ? 'Masquer' : 'Afficher',
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _visible = !_visible),
                ),
              ),
              onSubmitted: (_) => _valider(),
            ),
            const SizedBox(height: 10),
            // Le mot de passe est fixé ici puis transmis de vive voix: le
            // dire évite qu'on l'attende par courriel.
            Text(
              'Communiquez-le à la personne concernée. Elle devrait le '
              'changer à sa prochaine connexion.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 10),
              Text(
                _erreur!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          child: const Text('Réinitialiser'),
        ),
      ],
    );
  }
}
