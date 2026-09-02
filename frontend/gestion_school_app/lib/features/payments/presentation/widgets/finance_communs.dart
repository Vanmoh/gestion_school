import 'package:flutter/material.dart';

/// Ce que la page des finances et son dialogue d'encaissement partagent.
///
/// Les deux écrans avaient chacun leur pastille d'indicateur et leur mise en
/// forme des montants — deux composants, deux apparences, deux implémentations
/// du même calcul. Elles donnaient le même résultat, mais la première
/// correction — afficher les centimes, marquer un montant négatif — n'aurait
/// porté que sur l'une des deux.

/// Un chiffre et ce qu'il désigne, tels que la caisse les affiche.
///
/// Même grammaire que les indicateurs de la fiche d'un compte : le libellé
/// petit au-dessus, la valeur en gras dessous. La bordure vient du thème et
/// non d'un noir figé, qui disparaissait sur fond sombre.
class IndicateurFinance extends StatelessWidget {
  final String libelle;
  final String valeur;

  /// Colore la valeur : une trésorerie négative ne se lit pas comme les
  /// autres chiffres. Nul, la valeur prend l'encre courante.
  final Color? couleur;

  const IndicateurFinance({
    super.key,
    required this.libelle,
    required this.valeur,
    this.couleur,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            libelle,
            style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            valeur,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }
}

/// « 125 000 FCFA ». Les milliers séparés par une espace, comme on les écrit
/// ici, et la devise collée au nombre.
String montantEnFrancs(num valeur) {
  final entier = valeur.round();
  final chiffres = entier.abs().toString();
  final groupes = chiffres.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (correspondance) => '${correspondance[1]} ',
  );
  // Le signe se pose après le groupement: le glisser dans le compte des
  // chiffres décalerait les espaces d'un rang.
  final signe = entier < 0 ? '-' : '';
  return '$signe$groupes FCFA';
}

/// « 31/08/2026 ». Pour une échéance ou une date de dépense, où l'heure
/// n'apprend rien.
String dateEnJour(DateTime valeur) {
  final local = valeur.toLocal();
  final jour = local.day.toString().padLeft(2, '0');
  final mois = local.month.toString().padLeft(2, '0');
  return '$jour/$mois/${local.year}';
}

/// « 31/08/2026 14:32 ». Pour un encaissement, où deux règlements du même
/// jour ne se départagent que par l'heure.
String dateEnJourEtHeure(DateTime valeur) {
  final local = valeur.toLocal();
  final heure = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${dateEnJour(local)} $heure:$minute';
}

/// Un tableau sur grand écran, des fiches sur écran étroit.
///
/// Les listes du module s'affichaient en tableaux quelle que soit la largeur :
/// sur un téléphone, neuf colonnes se parcouraient latéralement — un geste que
/// l'application ne demande nulle part ailleurs.
///
/// Les fiches sont dérivées du tableau lui-même : chaque cellule reprend
/// l'en-tête de sa colonne. Il n'y a donc pas deux descriptions de la même
/// liste à tenir d'accord, et convertir une liste existante ne demande que de
/// remplacer son `DataTable` par ceci.
class TableauOuFiches extends StatelessWidget {
  final List<DataColumn> colonnes;
  final List<DataRow> lignes;

  /// En deçà, la liste passe en fiches. 720 pixels : au-delà, une tablette
  /// tient trois à quatre colonnes sans les serrer.
  final double seuil;

  /// Les colonnes dont l'en-tête n'apprend rien sur une fiche — une case à
  /// cocher, une colonne « Actions ». Leur cellule s'affiche sans libellé.
  final Set<int> colonnesSansLibelle;

  const TableauOuFiches({
    super.key,
    required this.colonnes,
    required this.lignes,
    this.seuil = 720,
    this.colonnesSansLibelle = const {},
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth >= seuil) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(columns: colonnes, rows: lignes),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final ligne in lignes) _fiche(context, ligne)],
        );
      },
    );
  }

  Widget _fiche(BuildContext context, DataRow ligne) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final choisir = ligne.onSelectChanged;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: ligne.selected ? scheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: choisir == null ? null : () => choisir(!ligne.selected),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < ligne.cells.length; index++)
                if (index < colonnes.length)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: colonnesSansLibelle.contains(index)
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: ligne.cells[index].child,
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 118,
                                child: DefaultTextStyle.merge(
                                  style: textTheme.labelSmall!.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  child: colonnes[index].label,
                                ),
                              ),
                              Expanded(child: ligne.cells[index].child),
                            ],
                          ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
