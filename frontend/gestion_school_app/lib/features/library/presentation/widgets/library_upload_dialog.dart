import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/library_repository.dart';
import '../../domain/library_collection.dart';

/// Le depot d'un PDF: ou le ranger, comment l'appeler, quel fichier.
///
/// L'ecole range ses documents sur ses propres etageres, jamais dans le
/// fonds importe -- celui-ci revient tel quel a la prochaine passe d'import
/// et il est partage par toutes les ecoles. La serie et la matiere se creent
/// donc depuis ce meme formulaire: obliger a les preparer ailleurs avant de
/// pouvoir deposer un premier fichier rendrait l'ecran inutilisable le jour
/// ou l'on en a besoin.
class LibraryUploadDialog extends StatefulWidget {
  final LibraryRepository depot;

  /// Toutes les series connues. Les communes sont ecartees a l'affichage:
  /// le serveur les refuserait, autant ne pas les proposer.
  final List<LibraryCollection> collections;

  const LibraryUploadDialog({
    super.key,
    required this.depot,
    required this.collections,
  });

  @override
  State<LibraryUploadDialog> createState() => _LibraryUploadDialogState();
}

/// Valeur du menu deroulant qui ouvre la saisie d'un nouveau nom.
const int _nouveau = -1;

class _LibraryUploadDialogState extends State<LibraryUploadDialog> {
  final _titreController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _nouvelleSerieController = TextEditingController();
  final _nouvelleMatiereController = TextEditingController();

  int? _serieId;
  int? _matiereId;
  PlatformFile? _fichier;
  bool _envoi = false;
  double? _progression;
  String? _erreur;

  List<LibraryCollection> get _series =>
      widget.collections.where((serie) => !serie.isCommun).toList();

  LibraryCollection? get _serieChoisie {
    for (final serie in _series) {
      if (serie.id == _serieId) return serie;
    }
    return null;
  }

  bool get _creeUneSerie => _serieId == _nouveau || _series.isEmpty;

  @override
  void initState() {
    super.initState();
    // Une seule etagere: la choisir d'office evite un menu a un seul item.
    _serieId = _series.length == 1 ? _series.first.id : (_series.isEmpty ? _nouveau : null);
  }

  @override
  void dispose() {
    _titreController.dispose();
    _descriptionController.dispose();
    _nouvelleSerieController.dispose();
    _nouvelleMatiereController.dispose();
    super.dispose();
  }

  Future<void> _choisirLeFichier() async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      // Sur le web il n'y a pas de chemin: seuls les octets arrivent, et
      // sans cette demande explicite ils restent nuls.
      withData: true,
    );
    final fichier = choix?.files.singleOrNull;
    if (fichier == null) return;

    setState(() {
      _fichier = fichier;
      _erreur = null;
      // Le nom du fichier fait un titre par defaut acceptable: c'est
      // toujours mieux qu'un champ vide, et il reste modifiable.
      if (_titreController.text.trim().isEmpty) {
        _titreController.text = _titreDepuis(fichier.name);
      }
    });
  }

  String _titreDepuis(String nomDeFichier) {
    final sansExtension = nomDeFichier.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return sansExtension.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  /// Un code court et sans accent, tire du libelle saisi.
  ///
  /// L'utilisateur nomme son etagere « Documents de l'école »; le code, lui,
  /// sert d'identifiant stable et tient en 40 caracteres.
  String _codeDepuis(String libelle) {
    final sansAccent = libelle
        .toLowerCase()
        .replaceAll(RegExp(r'[àâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[îï]'), 'i')
        .replaceAll(RegExp(r'[ôö]'), 'o')
        .replaceAll(RegExp(r'[ùûü]'), 'u')
        .replaceAll('ç', 'c');
    final code = sansAccent.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return code.length <= 40 ? code : code.substring(0, 40);
  }

  Future<void> _deposer() async {
    final fichier = _fichier;
    final titre = _titreController.text.trim();

    if (fichier == null) {
      setState(() => _erreur = 'Choisissez un fichier PDF.');
      return;
    }
    if (titre.isEmpty) {
      setState(() => _erreur = 'Donnez un titre au document.');
      return;
    }

    setState(() {
      _envoi = true;
      _erreur = null;
      _progression = null;
    });

    try {
      final matiereId = await _matiereDeDestination();
      final document = await widget.depot.uploadDocument(
        categoryId: matiereId,
        title: titre,
        fileName: fichier.name,
        bytes: fichier.bytes,
        filePath: fichier.bytes == null ? fichier.path : null,
        description: _descriptionController.text,
        onProgression: (fraction) {
          if (!mounted) return;
          setState(() => _progression = fraction);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(document);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _progression = null;
        _erreur = _message(error);
      });
    }
  }

  /// La matiere ou ranger le document, creee au passage si besoin.
  Future<int> _matiereDeDestination() async {
    var serieId = _serieId;

    if (_creeUneSerie) {
      final libelle = _nouvelleSerieController.text.trim();
      if (libelle.isEmpty) {
        throw const _SaisieIncomplete('Nommez la série à créer.');
      }
      final serie = await widget.depot.createCollection(
        code: _codeDepuis(libelle),
        label: libelle,
      );
      serieId = serie.id;
    }

    if (serieId == null) {
      throw const _SaisieIncomplete('Choisissez une série.');
    }

    if (_matiereId != null && _matiereId != _nouveau) {
      return _matiereId!;
    }

    final nom = _nouvelleMatiereController.text.trim();
    if (nom.isEmpty) {
      throw const _SaisieIncomplete('Nommez la matière à créer.');
    }
    return widget.depot.createCategory(collectionId: serieId, name: nom);
  }

  String _message(Object error) {
    if (error is _SaisieIncomplete) return error.message;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        // Le serveur renvoie ses refus champ par champ: « file », « title »,
        // « detail ». Les afficher tels quels vaut mieux qu'un « erreur 400 »
        // qui n'apprend rien -- c'est la qu'on lit « fichier trop volumineux ».
        final premier = data.values.firstWhere(
          (valeur) => valeur != null,
          orElse: () => null,
        );
        if (premier is List && premier.isNotEmpty) return premier.first.toString();
        if (premier != null) return premier.toString();
      }
    }
    return 'Dépôt impossible. $error';
  }

  @override
  Widget build(BuildContext context) {
    final serie = _serieChoisie;
    final matieres = serie?.categories ?? const <LibraryCategory>[];

    return AlertDialog(
      title: const Text('Ajouter un document'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_series.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  initialValue: _serieId,
                  decoration: const InputDecoration(labelText: 'Série'),
                  items: [
                    for (final item in _series)
                      DropdownMenuItem(value: item.id, child: Text(item.label)),
                    const DropdownMenuItem(
                      value: _nouveau,
                      child: Text('＋ Nouvelle série'),
                    ),
                  ],
                  onChanged: _envoi
                      ? null
                      : (valeur) => setState(() {
                          _serieId = valeur;
                          // La matiere appartenait a l'ancienne serie: la
                          // garder pointerait vers une etagere qu'on vient
                          // de quitter.
                          _matiereId = null;
                        }),
                ),
                const SizedBox(height: 10),
              ],
              if (_creeUneSerie)
                TextField(
                  controller: _nouvelleSerieController,
                  enabled: !_envoi,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la nouvelle série',
                    hintText: 'Documents de l’école',
                  ),
                ),
              if (_creeUneSerie) const SizedBox(height: 10),
              if (!_creeUneSerie && matieres.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  initialValue: _matiereId,
                  decoration: const InputDecoration(labelText: 'Matière'),
                  items: [
                    for (final matiere in matieres)
                      DropdownMenuItem(
                        value: matiere.id,
                        child: Text(matiere.name),
                      ),
                    const DropdownMenuItem(
                      value: _nouveau,
                      child: Text('＋ Nouvelle matière'),
                    ),
                  ],
                  onChanged: _envoi
                      ? null
                      : (valeur) => setState(() => _matiereId = valeur),
                ),
                const SizedBox(height: 10),
              ],
              if (_matiereId == null || _matiereId == _nouveau)
                TextField(
                  controller: _nouvelleMatiereController,
                  enabled: !_envoi,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la matière',
                    hintText: 'Règlement, Fiches de révision…',
                  ),
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _envoi ? null : _choisirLeFichier,
                icon: const Icon(Icons.attach_file),
                label: Text(_fichier?.name ?? 'Choisir un fichier PDF'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _titreController,
                enabled: !_envoi,
                decoration: const InputDecoration(labelText: 'Titre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionController,
                enabled: !_envoi,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description (facultatif)',
                ),
              ),
              if (_envoi) ...[
                const SizedBox(height: 14),
                // Chiffree des que le poids total est connu: un manuel
                // scanne part en plusieurs dizaines de secondes, et un rond
                // qui tourne ne dit pas si l'envoi avance.
                LinearProgressIndicator(value: _progression),
                const SizedBox(height: 6),
                Text(
                  _progression == null
                      ? 'Envoi en cours…'
                      : 'Envoi ${(_progression! * 100).clamp(0, 100).toStringAsFixed(0)} %',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(
                  _erreur!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _envoi ? null : _deposer,
          child: const Text('Déposer'),
        ),
      ],
    );
  }
}

/// Un champ manquant: c'est une consigne a l'utilisateur, pas une panne.
class _SaisieIncomplete implements Exception {
  final String message;
  const _SaisieIncomplete(this.message);
}
