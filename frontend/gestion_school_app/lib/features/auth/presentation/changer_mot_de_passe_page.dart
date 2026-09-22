import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';
import 'auth_controller.dart';

/// Choisir son mot de passe, à la première connexion.
///
/// Celui qu'on a reçu à l'inscription est écrit sur un papier et suit une
/// règle que l'école applique à tous — et l'identifiant est le matricule,
/// imprimé sur la carte scolaire. Tant qu'il n'est pas remplacé, le serveur
/// refuse tout le reste; cet écran est donc la seule porte, et il doit dire
/// pourquoi plutôt que de laisser l'élève buter sur un refus.
class ChangerMotDePassePage extends ConsumerStatefulWidget {
  const ChangerMotDePassePage({super.key});

  @override
  ConsumerState<ChangerMotDePassePage> createState() =>
      _ChangerMotDePassePageState();
}

class _ChangerMotDePassePageState extends ConsumerState<ChangerMotDePassePage> {
  final _nouveauController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _nouveauController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final nouveau = _nouveauController.text;
    final confirmation = _confirmationController.text;

    if (nouveau.length < 8) {
      setState(() => _erreur = 'Le mot de passe doit faire 8 caractères au moins.');
      return;
    }
    if (nouveau != confirmation) {
      setState(() => _erreur = 'Les deux saisies ne correspondent pas.');
      return;
    }

    setState(() {
      _enCours = true;
      _erreur = null;
    });

    // Saisi avant l'attente: s'en servir apres reviendrait a traverser le
    // contexte d'un ecran peut-etre demonte.
    final navigateur = Navigator.of(context);

    try {
      await AuthRepository(
        dio: ref.read(dioProvider),
        tokenStorage: ref.read(tokenStorageProvider),
      ).changerLeMotDePasse(nouveau: nouveau);

      // Le profil est relu: c'est lui qui porte l'obligation, et elle vient
      // de tomber.
      await ref.read(authControllerProvider.notifier).refreshCurrentUser();
      if (!mounted) return;

      final utilisateur = ref.read(authControllerProvider).value;
      navigateur.pushReplacementNamed(utilisateur?.homeRoute ?? '/login');
    } catch (error) {
      if (mounted) {
        setState(() => _erreur = _message(error));
      }
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  String _message(Object error) {
    final texte = error.toString();
    if (texte.contains('différent')) {
      return 'Choisissez un mot de passe différent de celui qui vous a été remis.';
    }
    return 'Le changement a échoué. Réessayez.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_reset, size: 34, color: scheme.primary),
                    const SizedBox(height: 14),
                    Text(
                      'Choisissez votre mot de passe',
                      style: textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Celui qui vous a été remis à l\'inscription est '
                      'provisoire : il est écrit sur un papier et suit la '
                      'même règle pour tout le monde.',
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('nouveau-mot-de-passe'),
                      controller: _nouveauController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nouveau mot de passe',
                        helperText: '8 caractères au moins',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('confirmation-mot-de-passe'),
                      controller: _confirmationController,
                      obscureText: true,
                      onSubmitted: (_) => _enCours ? null : _enregistrer(),
                      decoration: const InputDecoration(
                        labelText: 'Confirmez le mot de passe',
                      ),
                    ),
                    if (_erreur != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _erreur!,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('valider-mot-de-passe'),
                        onPressed: _enCours ? null : _enregistrer,
                        child: _enCours
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
