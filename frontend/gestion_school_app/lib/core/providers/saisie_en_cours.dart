import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Combien de saisies sont ouvertes à l'écran en ce moment.
///
/// Changer d'établissement ou d'année recharge **tout** ce qui est affiché.
/// Le faire pendant qu'un formulaire est rempli laisserait la saisie en
/// place avec les données d'une autre école — ce qui s'enregistrerait au
/// mauvais endroit sans que rien ne le signale.
///
/// Un compteur et non un booléen: deux formulaires peuvent être ouverts en
/// même temps, et le premier refermé ne doit pas lever la garde du second.
final saisieEnCoursProvider = StateProvider<int>((ref) => 0);

/// Déclare une saisie ouverte tant que ce widget est monté.
///
/// À placer autour d'un formulaire: le compteur monte à l'affichage, et
/// redescend à la fermeture, y compris quand l'écran est quitté sans
/// enregistrer.
class SaisieEnCours extends ConsumerStatefulWidget {
  final Widget child;

  /// Faux quand le formulaire est affiché mais vide: on ne garde que ce qui
  /// serait réellement perdu.
  final bool active;

  const SaisieEnCours({super.key, required this.child, this.active = true});

  @override
  ConsumerState<SaisieEnCours> createState() => _SaisieEnCoursState();
}

class _SaisieEnCoursState extends ConsumerState<SaisieEnCours> {
  bool _declaree = false;

  /// Le compteur, retenu des le montage.
  ///
  /// Riverpod interdit `ref` dans `dispose`: le lire la levait
  /// « Cannot use "ref" after the widget was disposed » a chaque fermeture
  /// de formulaire. La reference gardee ici survit au demontage du widget.
  StateController<int>? _compteur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _compteur = ref.read(saisieEnCoursProvider.notifier);
      _accorder();
    });
  }

  @override
  void didUpdateWidget(SaisieEnCours ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.active != widget.active) _accorder();
  }

  void _accorder() {
    final compteur = _compteur;
    if (compteur == null) return;

    if (widget.active && !_declaree) {
      _declaree = true;
      _differer(() => compteur.state++);
    } else if (!widget.active && _declaree) {
      _declaree = false;
      _differer(() => compteur.state--);
    }
  }

  /// Riverpod refuse qu'on modifie un provider pendant que l'arbre se
  /// construit -- ce qui est le cas dans `didUpdateWidget` comme dans
  /// `dispose`. Le report d'une micro-tache suffit a sortir du cycle.
  void _differer(void Function() action) {
    Future.microtask(action);
  }

  @override
  void dispose() {
    if (_declaree) {
      final compteur = _compteur;
      // Capture avant `super.dispose()`: le widget part, le compteur reste.
      if (compteur != null) _differer(() => compteur.state--);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Demande confirmation avant de changer de contexte pendant une saisie.
///
/// Rend vrai quand on peut poursuivre: soit rien n'était en cours, soit
/// l'utilisateur a accepté de perdre ce qu'il avait commencé.
Future<bool> confirmerChangementDeContexte(
  BuildContext context,
  WidgetRef ref, {
  required String quoi,
}) async {
  if (ref.read(saisieEnCoursProvider) <= 0) return true;

  final reponse = await showDialog<bool>(
    context: context,
    builder: (contexteDialogue) => AlertDialog(
      key: const Key('confirmer-changement-contexte'),
      title: const Text('Une saisie est en cours'),
      content: Text(
        'Changer $quoi rechargera tout l’écran. Ce que vous avez commencé à '
        'saisir sera perdu.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(contexteDialogue).pop(false),
          child: const Text('Rester ici'),
        ),
        FilledButton(
          key: const Key('changer-quand-meme'),
          onPressed: () => Navigator.of(contexteDialogue).pop(true),
          child: const Text('Changer quand même'),
        ),
      ],
    ),
  );
  return reponse == true;
}
