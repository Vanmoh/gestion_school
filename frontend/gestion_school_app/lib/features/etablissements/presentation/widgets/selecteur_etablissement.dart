import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/saisie_en_cours.dart';
import '../../../../core/widgets/cartouche_contexte.dart';
import '../../../../models/etablissement.dart';
import '../../../academics/presentation/annee_scolaire_controller.dart';
import '../../../auth/presentation/auth_controller.dart';

/// Le choix de l'établissement, dans le bandeau, à côté de l'année.
///
/// L'établissement n'y était qu'un texte: pour en changer, il fallait
/// repasser par le portail d'accueil et quitter son travail. Or c'est, avec
/// l'année, l'une des deux dimensions qui décident de ce que chaque écran
/// montre — les deux méritent le même geste.
///
/// Il ne se déroule que pour le super-administrateur: la coquille impose à
/// tous les autres l'établissement de leur compte, et un menu leur
/// promettrait une bascule qui les renverrait aussitôt à l'accueil.
class SelecteurEtablissement extends ConsumerWidget {
  final bool etendu;
  final bool surFondSombre;

  const SelecteurEtablissement({
    super.key,
    this.etendu = false,
    this.surFondSombre = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(etablissementProvider);
    final courant = provider.selected;
    final tous = provider.etablissements;
    final role = ref.watch(authControllerProvider).value?.role;
    final peutChanger = role == 'super_admin' && tous.length > 1;

    if (courant == null) {
      return CartoucheContexte(
        key: const Key('etablissement-absent'),
        icone: Icons.apartment_outlined,
        titre: 'Aucun établissement',
        etendu: etendu,
        surFondSombre: surFondSombre,
        teinte: Theme.of(context).colorScheme.error,
      );
    }

    final cartouche = CartoucheContexte(
      key: const Key('cartouche-etablissement'),
      icone: Icons.apartment_outlined,
      titre: courant.name,
      sousTitre: etendu ? _sousTitre(courant, tous.length, peutChanger) : null,
      etendu: etendu,
      surFondSombre: surFondSombre,
      deroulant: peutChanger,
      // Dire pourquoi il ne se déroule pas vaut mieux qu'un cartouche muet
      // sur lequel on clique sans effet.
      infobulle: peutChanger
          ? 'Changer d’établissement'
          : 'Ce compte est rattaché à cet établissement',
    );

    if (!peutChanger) return cartouche;

    return PopupMenuButton<int>(
      key: const Key('selecteur-etablissement'),
      tooltip: 'Établissement',
      position: PopupMenuPosition.under,
      onSelected: (id) async {
        final choisi = tous.firstWhere((etab) => etab.id == id);
        if (choisi.id == courant.id) return;

        // Un changement d'établissement recharge tout l'écran: ce qui était
        // en cours de saisie appartiendrait alors à une autre école.
        final feuVert = await confirmerChangementDeContexte(
          context,
          ref,
          quoi: 'd’établissement',
        );
        if (!feuVert) return;

        await ref.read(etablissementProvider).selectEtablissement(choisi);
        // Les années suivent l'établissement: celles d'une école n'ont aucun
        // sens dans une autre, et garder l'ancienne ferait travailler sur
        // une année que le serveur refusera.
        await ref.read(anneeScolaireProvider).charger();

        // Un changement d'établissement modifie tout ce qui est à l'écran:
        // le dire évite de croire à un écran qui n'a pas répondu.
        if (!context.mounted) return;
        final annee = ref.read(anneeScolaireProvider).selectionnee;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                annee == null
                    ? 'Vous travaillez maintenant sur ${choisi.name}.'
                    : 'Vous travaillez maintenant sur ${choisi.name} · '
                          '${annee.nom}.',
              ),
            ),
          );
      },
      itemBuilder: (context) => [
        for (final etab in tous)
          PopupMenuItem<int>(
            value: etab.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  child: etab.id == courant.id
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                Flexible(
                  child: Text(etab.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      child: cartouche,
    );
  }

  String _sousTitre(Etablissement courant, int total, bool peutChanger) {
    if (peutChanger) return '$total établissements';
    final ville = (courant.address ?? '').trim();
    return ville.isEmpty ? 'Établissement du compte' : ville;
  }
}
