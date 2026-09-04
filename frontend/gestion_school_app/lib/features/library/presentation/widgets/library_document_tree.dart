import 'package:flutter/material.dart';

import '../../domain/library_collection.dart';
import '../../domain/library_document.dart';

/// L'etagere: une serie, ses matieres repliees, ses documents.
///
/// Reprend la presentation de la source -- un dossier par matiere, son
/// compteur, ses PDF dedans -- parce que c'est ainsi que les eleves ont
/// appris a y chercher. Repliee par defaut: une serie de terminale compte
/// jusqu'a 322 documents, tout derouler noierait le premier regard.
///
/// Widget sans etat ni reseau: il recoit ce qu'il affiche, ce qui le rend
/// verifiable sans monter la page ni son transport.
class LibraryDocumentTree extends StatelessWidget {
  final List<LibraryCollection> collections;
  final int? selectedCollectionId;
  final List<LibraryDocument> documents;

  /// Filtre en cours. Non vide, l'arbre s'efface au profit d'une liste plate:
  /// une recherche traverse les matieres, la ranger par dossier la cacherait.
  final String recherche;

  /// Document en cours d'ouverture, pour ne pas laisser le clic sans reponse
  /// pendant le telechargement.
  final int? documentEnCours;

  /// Avancement de ce telechargement, de 0 a 1, ou null quand le poids total
  /// n'est pas connu. Les documents du fonds vont de 50 Ko a 127 Mo: un rond
  /// qui tourne ne distingue pas l'attente d'une seconde de celle d'une
  /// minute, et le lecteur clique une deuxieme fois en croyant que rien ne
  /// s'est passe.
  final double? progressionEnCours;

  final void Function(LibraryCollection collection) onCollectionChanged;
  final void Function(LibraryDocument document) onOuvrir;

  /// Renommer et supprimer, laisses a null quand le profil ne les a pas.
  ///
  /// Les proposer a qui n'y a pas droit ferait cliquer pour rien: la matrice
  /// ouvre l'ecriture a l'administration et au surveillant, la suppression a
  /// la seule administration. Ils ne portent de toute facon que sur les
  /// documents deposes -- le fonds commun revient tel quel au prochain
  /// import.
  final void Function(LibraryDocument document)? onRenommer;
  final void Function(LibraryDocument document)? onSupprimer;

  const LibraryDocumentTree({
    super.key,
    required this.collections,
    required this.selectedCollectionId,
    required this.documents,
    required this.recherche,
    required this.documentEnCours,
    this.progressionEnCours,
    required this.onCollectionChanged,
    required this.onOuvrir,
    this.onRenommer,
    this.onSupprimer,
  });

  LibraryCollection? get _serie {
    for (final collection in collections) {
      if (collection.id == selectedCollectionId) return collection;
    }
    return collections.isEmpty ? null : collections.first;
  }

  List<LibraryDocument> _documentsDe(LibraryCategory categorie) {
    return documents
        .where((document) => document.categoryId == categorie.id)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final serie = _serie;
    if (serie == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Aucune série dans le fonds.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selecteurDeSerie(context, serie),
        const SizedBox(height: 12),
        if (recherche.trim().isNotEmpty)
          _resultatsDeRecherche(context)
        else
          ...serie.categories.map((categorie) => _matiere(context, categorie)),
      ],
    );
  }

  Widget _selecteurDeSerie(BuildContext context, LibraryCollection active) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final collection in collections)
          ChoiceChip(
            // L'icone separe d'un coup d'oeil les annales communes des
            // etageres que l'ecole s'est constituees: les deux se melent
            // dans la meme rangee de puces.
            avatar: collection.isCommun
                ? null
                : const Icon(Icons.school_outlined, size: 18),
            label: Text('${collection.label} (${collection.documentCount})'),
            selected: collection.id == active.id,
            onSelected: (_) => onCollectionChanged(collection),
          ),
      ],
    );
  }

  Widget _resultatsDeRecherche(BuildContext context) {
    if (documents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Aucun document ne porte ces mots.'),
      );
    }
    return Column(
      children: [
        for (final document in documents) _ligne(context, document, matiere: true),
      ],
    );
  }

  Widget _matiere(BuildContext context, LibraryCategory categorie) {
    final lignes = _documentsDe(categorie);
    return ExpansionTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(categorie.name),
      subtitle: Text(
        '${categorie.documentCount} document'
        '${categorie.documentCount > 1 ? 's' : ''}',
      ),
      childrenPadding: const EdgeInsets.only(left: 12, right: 4, bottom: 8),
      children: lignes.isEmpty
          ? const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text('Documents non chargés.'),
              ),
            ]
          : [for (final document in lignes) _ligne(context, document)],
    );
  }

  Widget _ligne(
    BuildContext context,
    LibraryDocument document, {
    bool matiere = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final enCours = documentEnCours == document.id;

    // Les documents que la source refuse restent au catalogue, mais ils ne
    // s'ouvriront pas: le dire vaut mieux qu'un echec au clic. Sur un serveur
    // sans Internet, c'est vrai de tout document non rapatrie, que la source
    // l'ait refuse ou non -- `isReadable` porte ce second cas.
    final refuseALaSource =
        !document.isDownloaded && document.importError.isNotEmpty;
    final indisponible = refuseALaSource || !document.isReadable;

    final details = <String>[
      if (matiere && document.categoryName.isNotEmpty) document.categoryName,
      if (document.tailleLisible.isNotEmpty) document.tailleLisible,
      if (document.estDepose && document.uploadedByName.isNotEmpty)
        'ajouté par ${document.uploadedByName}',
      if (document.description.isNotEmpty) document.description,
      if (refuseALaSource)
        'indisponible à la source'
      else if (indisponible)
        'non rapatrié sur ce serveur',
    ];

    return ListTile(
      dense: true,
      leading: Icon(
        Icons.picture_as_pdf_outlined,
        color: indisponible ? scheme.onSurfaceVariant : scheme.primary,
      ),
      title: Text(document.title),
      subtitle: details.isEmpty ? null : Text(details.join('  ·  ')),
      trailing: enCours
          ? _avancement(context)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: indisponible ? 'Indisponible' : 'Ouvrir',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: indisponible ? null : () => onOuvrir(document),
                ),
                if (_actionsDe(document).isNotEmpty) _menuActions(context, document),
              ],
            ),
      onTap: indisponible || enCours ? null : () => onOuvrir(document),
    );
  }

  /// Ce que le profil peut faire sur ce document, dans l'ordre du menu.
  List<String> _actionsDe(LibraryDocument document) {
    if (!document.estDepose) return const [];
    return [
      if (onRenommer != null) 'renommer',
      if (onSupprimer != null) 'supprimer',
    ];
  }

  Widget _menuActions(BuildContext context, LibraryDocument document) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        if (action == 'renommer') onRenommer?.call(document);
        if (action == 'supprimer') onSupprimer?.call(document);
      },
      itemBuilder: (_) => [
        for (final action in _actionsDe(document))
          PopupMenuItem<String>(
            value: action,
            child: Row(
              children: [
                Icon(
                  action == 'renommer'
                      ? Icons.edit_outlined
                      : Icons.delete_outline,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(action == 'renommer' ? 'Modifier' : 'Supprimer'),
              ],
            ),
          ),
      ],
    );
  }

  /// Le rond de progression, chiffre des que la taille est connue.
  Widget _avancement(BuildContext context) {
    final fraction = progressionEnCours;
    final rond = SizedBox(
      width: 18,
      height: 18,
      // value null redonne l'animation indeterminee: c'est le bon affichage
      // tant qu'on ignore la taille, et le mauvais des qu'on la connait.
      child: CircularProgressIndicator(strokeWidth: 2, value: fraction),
    );
    if (fraction == null) {
      return rond;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)} %',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(width: 8),
        rond,
      ],
    );
  }
}
