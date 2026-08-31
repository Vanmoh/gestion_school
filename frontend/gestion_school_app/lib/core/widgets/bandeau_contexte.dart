import 'package:flutter/material.dart';

import '../../features/academics/presentation/widgets/selecteur_annee_scolaire.dart';
import '../../features/etablissements/presentation/widgets/selecteur_etablissement.dart';

/// Où je travaille: l'établissement et l'année, côte à côte.
///
/// Ce sont les deux dimensions qui décident de ce que chaque écran montre.
/// Elles étaient traitées différemment — l'année se changeait d'un clic,
/// l'établissement demandait de repasser par le portail d'accueil et de
/// quitter son travail. Les réunir dans un même bloc en fait ce qu'elles
/// sont: une paire, lue d'un seul regard.
class BandeauContexte extends StatelessWidget {
  /// Vrai dans l'en-tête de bureau: chaque cartouche montre alors sa ligne
  /// de détail — la période de l'année, le nombre d'établissements.
  final bool etendu;

  /// Vrai sur le fond sombre du bandeau, qui a son propre vocabulaire.
  final bool surFondSombre;

  const BandeauContexte({
    super.key,
    this.etendu = false,
    this.surFondSombre = false,
  });

  @override
  Widget build(BuildContext context) {
    final separateur = surFondSombre
        ? Colors.white.withValues(alpha: 0.2)
        : Theme.of(context).colorScheme.outlineVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Une borne haute plutot qu'un `Flexible` nu: le nom d'ecole cede la
        // place au-dela, mais l'annee -- dont le libelle est court et connu
        // d'avance -- n'a plus a se faire tronquer en « 2025-2... » parce que
        // le voisin s'etale.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: etendu ? 260 : 170),
          child: SelecteurEtablissement(
            etendu: etendu,
            surFondSombre: surFondSombre,
          ),
        ),
        // Un trait plutôt qu'un espace: il dit que les deux vont ensemble
        // sans les confondre.
        Container(
          width: 1,
          height: etendu ? 30 : 22,
          margin: EdgeInsets.symmetric(horizontal: etendu ? 12 : 8),
          color: separateur,
        ),
        SelecteurAnneeScolaire(
          etendu: etendu,
          surFondSombre: surFondSombre,
        ),
      ],
    );
  }
}
