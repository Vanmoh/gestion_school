/// Les palettes du module Academique: une classe, ou une matiere.
///
/// Meme grammaire que les palettes eleve, enseignant et compte: en-tete
/// identifiant, blocs de champs, actions sous le nom. Le module ne montrait
/// jusqu'ici que deux tableaux pagines: pour savoir ce que portait une classe,
/// il fallait lire la ligne, puis chercher ses matieres dans l'autre tableau.
library;

import 'package:flutter/material.dart';

/// Ce qui est commun aux deux palettes: le cadre, l'en-tete, les blocs.
class _Cadre extends StatelessWidget {
  final IconData icone;
  final String titre;
  final List<Widget> pastilles;
  final List<Widget> actions;
  final VoidCallback? onClear;
  final Widget corps;

  const _Cadre({
    required this.icone,
    required this.titre,
    required this.pastilles,
    required this.actions,
    required this.onClear,
    required this.corps,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icone,
                    size: 30,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titre,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (pastilles.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: pastilles,
                        ),
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    ],
                  ),
                ),
                if (onClear != null)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Résultats'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            corps,
          ],
        ),
      ),
    );
  }
}

const _nonRenseigne = 'Non renseigné';

Widget _pastille(
  ColorScheme scheme,
  TextTheme textTheme,
  String texte, {
  Color? couleur,
  Color? texteCouleur,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: couleur ?? scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      texte,
      style: textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: texteCouleur ?? scheme.onSecondaryContainer,
      ),
    ),
  );
}

Widget _bloc(
  ColorScheme scheme,
  TextTheme textTheme,
  String titre,
  List<(String, String)> champs,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        titre.toUpperCase(),
        style: textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(height: 8),
      for (final (label, valeur) in champs)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                valeur.trim().isEmpty ? _nonRenseigne : valeur,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: valeur.trim().isEmpty
                      ? FontWeight.w400
                      : FontWeight.w600,
                  fontStyle: valeur.trim().isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: valeur.trim().isEmpty ? scheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

String _texte(dynamic valeur) => (valeur ?? '').toString().trim();

int _entier(dynamic valeur) {
  if (valeur is int) return valeur;
  return int.tryParse(_texte(valeur)) ?? 0;
}

/// Ce qu'il faut savoir d'une classe pour agir dessus.
///
/// Les matieres qu'elle porte sont listees ici: c'est la question qu'on se
/// pose devant une classe, et elle demandait jusqu'ici de lire l'autre
/// tableau ligne a ligne.
class ClassePaletteCard extends StatelessWidget {
  final Map<String, dynamic> classe;

  /// Le nom de l'année scolaire, resolu par l'appelant qui porte la table.
  final String anneeNom;

  /// Les matieres rattachees a cette classe.
  final List<Map<String, dynamic>> matieres;

  final List<Widget> actions;
  final VoidCallback? onClear;

  /// Ouvre la palette d'une matiere depuis la liste: on suit le fil sans
  /// repasser par la recherche.
  final void Function(Map<String, dynamic> matiere)? onOuvrirMatiere;

  const ClassePaletteCard({
    super.key,
    required this.classe,
    required this.anneeNom,
    this.matieres = const [],
    this.actions = const [],
    this.onClear,
    this.onOuvrirMatiere,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final effectif = _entier(classe['student_count']);

    return _Cadre(
      icone: Icons.meeting_room_outlined,
      titre: _texte(classe['name']).isEmpty ? 'Classe' : _texte(classe['name']),
      pastilles: [
        _pastille(scheme, textTheme, 'Classe'),
        if (anneeNom.trim().isNotEmpty)
          _pastille(scheme, textTheme, anneeNom.trim()),
      ],
      actions: actions,
      onClear: onClear,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final colonnes = constraints.maxWidth > 560 ? 2 : 1;
              final largeur =
                  (constraints.maxWidth - (colonnes - 1) * 16) / colonnes;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: largeur,
                    child: _bloc(scheme, textTheme, 'Classe', [
                      ('Nom', _texte(classe['name'])),
                      ('Année scolaire', anneeNom),
                    ]),
                  ),
                  SizedBox(
                    width: largeur,
                    child: _bloc(scheme, textTheme, 'Effectifs', [
                      (
                        'Élèves inscrits',
                        // Zero se dit: une classe vide et une classe dont le
                        // compte manque ne demandent pas la meme chose.
                        '$effectif élève${effectif > 1 ? 's' : ''}',
                      ),
                      ('Matières', '${matieres.length}'),
                    ]),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'MATIÈRES DE LA CLASSE',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          if (matieres.isEmpty)
            Text(
              'Aucune matière rattachée à cette classe.',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final matiere in matieres)
                  ActionChip(
                    avatar: const Icon(Icons.menu_book_outlined, size: 16),
                    label: Text(
                      _texte(matiere['code']).isEmpty
                          ? _texte(matiere['name'])
                          : '${_texte(matiere['name'])} · ${_texte(matiere['code'])}',
                    ),
                    onPressed: onOuvrirMatiere == null
                        ? null
                        : () => onOuvrirMatiere!(matiere),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Ce qu'il faut savoir d'une matiere pour agir dessus.
///
/// Le coefficient et la classe de rattachement y figurent: une matiere n'a de
/// sens que rapportee a sa classe, le meme intitule pouvant porter un code et
/// un coefficient differents ailleurs.
class MatierePaletteCard extends StatelessWidget {
  final Map<String, dynamic> matiere;

  /// Nom de la classe de rattachement, resolu par l'appelant.
  final String classeNom;

  final List<Widget> actions;
  final VoidCallback? onClear;

  /// Ouvre la palette de la classe de rattachement.
  final VoidCallback? onOuvrirClasse;

  const MatierePaletteCard({
    super.key,
    required this.matiere,
    required this.classeNom,
    this.actions = const [],
    this.onClear,
    this.onOuvrirClasse,
  });

  /// Le coefficient tel qu'il se lit: « 2 » plutot que « 2.00 ».
  static String coefficientLisible(dynamic brut) {
    final texte = _texte(brut);
    if (texte.isEmpty) return '';
    final valeur = double.tryParse(texte);
    if (valeur == null) return texte;
    if (valeur == valeur.roundToDouble()) return valeur.toInt().toString();
    return valeur
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final coefficient = coefficientLisible(matiere['coefficient']);

    return _Cadre(
      icone: Icons.menu_book_outlined,
      titre: _texte(matiere['name']).isEmpty
          ? 'Matière'
          : _texte(matiere['name']),
      pastilles: [
        _pastille(scheme, textTheme, 'Matière'),
        if (_texte(matiere['code']).isNotEmpty)
          _pastille(scheme, textTheme, _texte(matiere['code'])),
      ],
      actions: actions,
      onClear: onClear,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final colonnes = constraints.maxWidth > 560 ? 2 : 1;
              final largeur =
                  (constraints.maxWidth - (colonnes - 1) * 16) / colonnes;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: largeur,
                    child: _bloc(scheme, textTheme, 'Matière', [
                      ('Intitulé', _texte(matiere['name'])),
                      ('Code', _texte(matiere['code'])),
                    ]),
                  ),
                  SizedBox(
                    width: largeur,
                    child: _bloc(scheme, textTheme, 'Barème', [
                      ('Coefficient', coefficient),
                      ('Classe', classeNom),
                    ]),
                  ),
                ],
              );
            },
          ),
          if (onOuvrirClasse != null && classeNom.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onOuvrirClasse,
                icon: const Icon(Icons.meeting_room_outlined, size: 18),
                label: Text('Ouvrir la classe ${classeNom.trim()}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
