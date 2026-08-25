import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../domain/library_collection.dart';
import '../domain/library_document.dart';
import 'library_controller.dart';
import 'widgets/library_document_tree.dart';

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

  @override
  Widget build(BuildContext context) {
    final total = _collections.fold<int>(
      0,
      (somme, collection) => somme + collection.documentCount,
    );

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
                Text(
                  _collections.isEmpty
                      ? 'Aucun document importé pour l’instant.'
                      : '${_collections.length} séries · $total documents',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                // La provenance reste affichee: ce fonds n'est pas de l'ecole.
                Text(
                  'Source : BKalan',
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
        ),
      ],
    );
  }
}
