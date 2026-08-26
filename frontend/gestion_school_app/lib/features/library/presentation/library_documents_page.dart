import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/permissions/module_permissions.dart';
import '../domain/library_collection.dart';
import '../domain/library_document.dart';
import 'library_controller.dart';
import 'widgets/library_document_tree.dart';
import 'widgets/library_upload_dialog.dart';

/// Le fonds documentaire: annales, cours et brochures par serie et par
/// matiere.
///
/// La rubrique « Bibliotheque » ne connaissait que l'ouvrage physique -- un
/// titre, un ISBN, des exemplaires a rendre. Les documents que les eleves
/// s'echangent en PDF n'avaient aucun endroit ou vivre.
class LibraryDocumentsPage extends ConsumerStatefulWidget {
  const LibraryDocumentsPage({super.key});

  @override
  ConsumerState<LibraryDocumentsPage> createState() =>
      _LibraryDocumentsPageState();
}

class _LibraryDocumentsPageState extends ConsumerState<LibraryDocumentsPage> {
  final _rechercheController = TextEditingController();

  bool _chargement = true;
  String? _erreur;
  List<LibraryCollection> _collections = const [];
  List<LibraryDocument> _documents = const [];
  int? _serieChoisie;
  int? _documentEnCours;
  /// Fraction telechargee du document en cours, null tant que le poids total
  /// n'est pas connu.
  double? _progressionEnCours;
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final depot = ref.read(libraryRepositoryProvider);
      final collections = await depot.fetchCollections();
      if (!mounted) return;

      final serie = _serieChoisie ??
          (collections.isEmpty ? null : collections.first.id);
      setState(() {
        _collections = collections;
        _serieChoisie = serie;
      });

      if (serie != null) {
        await _chargerDocuments(serie);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _erreur = _message(error, 'Erreur chargement du fonds.'));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _chargerDocuments(int collectionId) async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final documents = await ref
          .read(libraryRepositoryProvider)
          .fetchDocuments(collectionId: collectionId, search: _recherche);
      if (!mounted) return;
      setState(() => _documents = documents);
    } catch (error) {
      if (!mounted) return;
      setState(() => _erreur = _message(error, 'Erreur chargement des documents.'));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  /// Ouvre le PDF dans la visionneuse du systeme.
  ///
  /// Passe par l'API et non par l'URL d'origine: c'est le serveur qui sait
  /// si le fichier est deja rapatrie, et une URL exterieure donnee au
  /// navigateur echouerait en CORS.
  Future<void> _ouvrir(LibraryDocument document) async {
    setState(() {
      _documentEnCours = document.id;
      _progressionEnCours = null;
    });
    try {
      final octets = await ref
          .read(libraryRepositoryProvider)
          .fetchDocumentFile(
            document.id,
            onProgression: (fraction) {
              // L'ecran peut avoir ete quitte pendant un telechargement long.
              if (!mounted || _documentEnCours != document.id) return;
              setState(() => _progressionEnCours = fraction);
            },
          );
      if (!mounted) return;
      if (octets.isEmpty) {
        _signaler('Document vide.');
        return;
      }
      await Printing.layoutPdf(
        onLayout: (_) async => octets,
        name: document.title,
      );
    } catch (error) {
      _signaler(_message(error, 'Impossible d’ouvrir ce document.'));
    } finally {
      if (mounted) {
        setState(() {
          _documentEnCours = null;
          _progressionEnCours = null;
        });
      }
    }
  }

  String _message(Object error, String repli) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
      if (error.response?.statusCode == 404) {
        return 'L’API utilisée ne contient pas encore le fonds documentaire. '
            'Redémarre le backend ou reconfigure l’URL API.';
      }
    }
    return '$repli $error';
  }

  void _signaler(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Depot et gestion des documents de l'ecole --------------------------

  /// Ouvre le formulaire de depot, puis recharge sur la serie qui l'a recu.
  ///
  /// Recharger tout et non la seule liste courante: le depot a pu creer une
  /// serie ou une matiere, et les compteurs de l'arbre viennent du serveur.
  Future<void> _ajouterUnDocument() async {
    final document = await showDialog<LibraryDocument>(
      context: context,
      builder: (_) => LibraryUploadDialog(
        depot: ref.read(libraryRepositoryProvider),
        collections: _collections,
      ),
    );
    if (document == null || !mounted) return;

    _signaler('Document « ${document.title} » ajouté.');
    await _rechargerSurLaSerieDe(document);
  }

  /// Recharge le catalogue en se placant sur la serie qui porte ce document.
  Future<void> _rechargerSurLaSerieDe(LibraryDocument document) async {
    final collections = await ref.read(libraryRepositoryProvider).fetchCollections();
    if (!mounted) return;

    // La matiere du document dit sa serie: sans ce calage, un depot dans une
    // etagere fraichement creee laisserait l'ecran sur l'ancienne, et le
    // document paraitrait perdu.
    int? serie = _serieChoisie;
    for (final collection in collections) {
      final porte = collection.categories.any(
        (categorie) => categorie.id == document.categoryId,
      );
      if (porte) {
        serie = collection.id;
        break;
      }
    }

    setState(() {
      _collections = collections;
      _serieChoisie = serie;
    });
    if (serie != null) await _chargerDocuments(serie);
  }

  Future<void> _renommer(LibraryDocument document) async {
    final titreController = TextEditingController(text: document.title);
    final descriptionController = TextEditingController(text: document.description);

    final valide = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text('Modifier le document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titreController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (facultatif)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    final titre = titreController.text.trim();
    titreController.dispose();
    final description = descriptionController.text;
    descriptionController.dispose();

    if (valide != true || titre.isEmpty || !mounted) return;

    try {
      await ref.read(libraryRepositoryProvider).updateDocument(
            document.id,
            title: titre,
            description: description,
          );
      if (!mounted) return;
      _signaler('Document modifié.');
      final serie = _serieChoisie;
      if (serie != null) await _chargerDocuments(serie);
    } catch (error) {
      _signaler(_message(error, 'Modification impossible.'));
    }
  }

  Future<void> _supprimer(LibraryDocument document) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: const Text('Supprimer le document'),
        content: Text(
          '« ${document.title} » sera retiré du fonds et son fichier effacé. '
          'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    try {
      await ref.read(libraryRepositoryProvider).deleteDocument(document.id);
      if (!mounted) return;
      _signaler('Document supprimé.');
      // Le compteur de la matiere vient du serveur: relire la seule liste
      // laisserait « 4 documents » sur une matiere qui n'en a plus que trois.
      await _charger();
    } catch (error) {
      _signaler(_message(error, 'Suppression impossible.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _collections.fold<int>(
      0,
      (somme, collection) => somme + collection.documentCount,
    );
    final droits = ref.watch(currentPermissionsProvider);
    final peutDeposer = droits.canWrite('library');
    final peutSupprimer = droits.canDelete('library');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Fonds documentaire',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualiser',
                      onPressed: _chargement ? null : _charger,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (peutDeposer) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _chargement ? null : _ajouterUnDocument,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Ajouter un document'),
                    ),
                  ),
                ],
                Text(
                  _collections.isEmpty
                      ? 'Aucun document importé pour l’instant.'
                      : '${_collections.length} séries · $total documents',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                // La provenance reste affichee: le fonds commun n'est pas de
                // l'ecole, et ce qu'elle depose ne sort pas de chez elle.
                Text(
                  'Fonds commun : BKalan · les documents que vous ajoutez '
                  'restent visibles de votre seul établissement',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rechercheController,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Rechercher un document dans la série',
                    border: const OutlineInputBorder(),
                    suffixIcon: _recherche.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _rechercheController.clear();
                              setState(() => _recherche = '');
                              final serie = _serieChoisie;
                              if (serie != null) _chargerDocuments(serie);
                            },
                          ),
                  ),
                  onSubmitted: (valeur) {
                    setState(() => _recherche = valeur);
                    final serie = _serieChoisie;
                    if (serie != null) _chargerDocuments(serie);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_erreur != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _erreur!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_chargement) const LinearProgressIndicator(),
        LibraryDocumentTree(
          collections: _collections,
          selectedCollectionId: _serieChoisie,
          documents: _documents,
          recherche: _recherche,
          documentEnCours: _documentEnCours,
          progressionEnCours: _progressionEnCours,
          onCollectionChanged: (collection) {
            setState(() => _serieChoisie = collection.id);
            _chargerDocuments(collection.id);
          },
          onOuvrir: _ouvrir,
          // Null quand le profil n'a pas le droit: l'arbre n'affiche alors
          // aucun menu plutot qu'un menu qui echouerait.
          onRenommer: peutDeposer ? _renommer : null,
          onSupprimer: peutSupprimer ? _supprimer : null,
        ),
      ],
    );
  }
}
