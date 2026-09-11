import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/permissions/module_permissions.dart';

import '../../../core/network/api_client.dart';
import '../../../models/etablissement.dart';

import '../../../core/widgets/barre_recherche_module.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  static const List<String> _backupBases = <String>[
    '/backup-archives',
    '/common/backup-archives',
  ];

  bool _loading = true;
  bool _busy = false;

  /// Filtre de l'historique. L'ecran empilait toutes les archives sans moyen
  /// d'en retrouver une: passe quelques semaines, la liste se parcourt a la
  /// molette.
  final _rechercheController = TextEditingController();
  String _recherche = '';
  bool _historyRefreshing = false;
  List<Map<String, dynamic>> _rows = [];
  Timer? _historyAutoRefreshTimer;
  DateTime? _forcePollingUntil;

  static const Duration _backupConnectTimeout = Duration(minutes: 2);
  static const Duration _backupTransferTimeout = Duration(minutes: 10);

  String _createScope = 'établissement';
  bool _includeMedia = true;
  /// La bibliotheque decochee par defaut. Elle pese a elle seule des
  /// milliers de fois le reste des medias -- annales et manuels importes,
  /// identiques d'une ecole a l'autre et reconstituables par l'import.
  /// Cochee sans le savoir, elle rendait chaque sauvegarde interminable.
  bool _includeLibrary = false;
  final TextEditingController _notesController = TextEditingController();

  /// Ce que pese le dossier des medias, mesure par le serveur. Sert a
  /// annoncer le volume avant de lancer, plutot que de faire cocher une
  /// case a l'aveugle.
  Map<String, dynamic>? _volumes;

  String _restoreScope = 'établissement';
  PlatformFile? _restoreFile;
  final TextEditingController _restoreNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    _historyAutoRefreshTimer?.cancel();
    _notesController.dispose();
    _restoreNotesController.dispose();
    _rechercheController.dispose();
    super.dispose();
  }

  Future<void> _loadRows({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }
    try {
      final response = await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).get(
          '$base/',
          options: _backupRequestOptions(),
        ),
      );
      final data = response.data;
      final List<dynamic> raw =
          data is Map<String, dynamic> && data['results'] is List<dynamic>
          ? data['results'] as List<dynamic>
          : (data is List<dynamic> ? data : <dynamic>[]);
      setState(() {
        _rows = raw
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      });
      _syncHistoryAutoRefresh();
    } catch (error) {
      if (showLoading) {
        _showMessage('Erreur chargement backups: $error');
      }
    } finally {
      if (mounted && showLoading) {
        setState(() => _loading = false);
      }
    }

    if (showLoading) {
      // Apres l'historique, pas avant: la mesure parcourt le disque et n'a
      // pas a retarder l'affichage de la liste.
      await _chargerLesVolumes();
    }
  }

  /// Mesure le dossier des medias cote serveur. Un echec reste muet: c'est
  /// un renseignement de confort, la sauvegarde marche sans lui.
  Future<void> _chargerLesVolumes() async {
    try {
      final response = await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).get(
          '$base/volumes/',
          options: _backupRequestOptions(),
        ),
      );
      final data = response.data;
      if (mounted && data is Map<String, dynamic>) {
        setState(() => _volumes = data);
      }
    } catch (_) {
      // Serveur plus ancien, ou route absente: on n'annonce rien.
    }
  }

  int _volume(String cle) {
    final brut = _volumes?[cle];
    if (brut is int) return brut;
    return int.tryParse(brut?.toString() ?? '') ?? 0;
  }

  /// Vrai tant qu'une archive s'ecrit ou se restaure. Les deux operations
  /// entretiennent le rafraichissement: la sauvegarde aussi se suit
  /// desormais en direct, et pas seulement la restauration.
  bool _uneOperationEstEnCours() {
    for (final row in _rows) {
      final status = (row['status']?.toString() ?? '').toLowerCase();
      if (status == 'running' || status == 'pending') {
        return true;
      }
    }
    return false;
  }

  bool _shouldForcePolling() {
    final until = _forcePollingUntil;
    if (until == null) {
      return false;
    }
    return DateTime.now().isBefore(until);
  }

  void _syncHistoryAutoRefresh() {
    final shouldRefresh = _uneOperationEstEnCours() || _shouldForcePolling();
    if (!shouldRefresh) {
      _historyAutoRefreshTimer?.cancel();
      _historyAutoRefreshTimer = null;
      return;
    }
    if (_historyAutoRefreshTimer != null) {
      return;
    }

    _historyAutoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || _busy || _historyRefreshing) {
        return;
      }
      _historyRefreshing = true;
      try {
        await _loadRows(showLoading: false);
      } finally {
        _historyRefreshing = false;
      }
    });
  }

  Future<void> _createBackup() async {
    await _runBusyTask(() async {
      final selectedEtab = ref.read(etablissementProvider).selected;
      final payload = <String, dynamic>{
        'scope': _createScope,
        'include_media': _includeMedia,
        'include_library_documents': _includeMedia && _includeLibrary,
        'notes': _notesController.text.trim(),
      };
      if (_createScope == 'établissement' && selectedEtab != null) {
        payload['etablissement_id'] = selectedEtab.id;
      }

      // L'archive s'ecrit dans un processus a part: la reponse arrive tout de
      // suite, et c'est l'historique qui montre l'avancement. On demarre donc
      // le rafraichissement avant meme que la ligne existe.
      _forcePollingUntil = DateTime.now().add(const Duration(minutes: 2));
      _syncHistoryAutoRefresh();
      await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).post(
          '$base/',
          data: payload,
          options: _backupRequestOptions(),
        ),
      );
      _showMessage(
        'Sauvegarde lancée. Son avancement s\'affiche dans l\'historique.',
        isSuccess: true,
      );
      await _loadRows();
    });
  }

  /// Efface une archive, apres confirmation nommee.
  Future<void> _supprimerArchive(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) {
      _showMessage('Backup invalide.');
      return;
    }

    final nom = row['filename']?.toString().isNotEmpty == true
        ? row['filename'].toString()
        : 'Archive #$id';
    final poids = _tailleLisible(_octets(row));
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer cette archive ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$nom sera effacée du serveur.'),
            if (poids != '—') ...[
              const SizedBox(height: 8),
              Text('Espace libéré : $poids'),
            ],
            const SizedBox(height: 8),
            const Text(
              'Elle ne pourra plus servir à restaurer. '
              'Téléchargez-la d\'abord si vous voulez la garder.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirmer-suppression-archive'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    await _runBusyTask(() async {
      await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).delete(
          '$base/$id/',
          options: _backupRequestOptions(),
        ),
      );
      _showMessage('Archive supprimée.', isSuccess: true);
      await _loadRows();
    });
  }

  /// Ne garde que les archives les plus recentes. Sans ce menage, une
  /// sauvegarde hebdomadaire remplit le disque du serveur en quelques mois.
  Future<void> _nettoyerLHistorique() async {
    var conserver = 3;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => AlertDialog(
          title: const Text('Nettoyer l\'historique'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Les archives les plus récentes sont gardées, '
                'les plus anciennes sont effacées.',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: conserver,
                decoration: const InputDecoration(
                  labelText: 'Archives à conserver',
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('La dernière seulement')),
                  DropdownMenuItem(value: 3, child: Text('Les 3 dernières')),
                  DropdownMenuItem(value: 5, child: Text('Les 5 dernières')),
                  DropdownMenuItem(value: 10, child: Text('Les 10 dernières')),
                ],
                onChanged: (valeur) {
                  if (valeur != null) {
                    setDialogState(() => conserver = valeur);
                  }
                },
              ),
              const SizedBox(height: 10),
              const Text('Une sauvegarde en cours n\'est jamais touchée.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const Key('confirmer-nettoyage-archives'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Nettoyer'),
            ),
          ],
        ),
      ),
    );
    if (confirme != true) return;

    await _runBusyTask(() async {
      final response = await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).post(
          '$base/purge/',
          data: {'conserver': conserver},
          options: _backupRequestOptions(),
        ),
      );
      final data = response.data;
      final supprimees = data is Map<String, dynamic>
          ? (data['supprimees'] as num?)?.toInt() ?? 0
          : 0;
      final liberes = data is Map<String, dynamic>
          ? (data['octets_liberes'] as num?)?.toInt() ?? 0
          : 0;
      _showMessage(
        supprimees == 0
            ? 'Rien à nettoyer : aucune archive plus ancienne à effacer.'
            : '$supprimees archive${supprimees > 1 ? 's' : ''} supprimée'
                  '${supprimees > 1 ? 's' : ''}, '
                  '${_tailleLisible(liberes)} libérés.',
        isSuccess: true,
      );
      await _loadRows();
    });
  }

  Future<void> _downloadBackup(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) {
      _showMessage('Backup invalide.');
      return;
    }

    await _runBusyTask(() async {
      final response = await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).get(
          '$base/$id/download/',
          options: _backupRequestOptions(responseType: ResponseType.bytes),
        ),
      );
      final bytes = _toBytes(response.data);
      final fileName = (row['filename']?.toString().trim().isNotEmpty ?? false)
          ? row['filename'].toString().trim()
          : 'backup_$id.zip';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la sauvegarde',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: bytes,
      );

      if (savePath == null) {
        if (kIsWeb) {
          _showMessage('Telechargement effectué avec succès.', isSuccess: true);
          return;
        }
        _showMessage('Téléchargement annulé.');
        return;
      }
      _showMessage('Fichier sauvegardé: $fileName', isSuccess: true);
    });
  }

  Future<void> _restoreFromArchive(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) {
      _showMessage('Backup invalide.');
      return;
    }

    // Le geste le plus destructeur de l'application se declenchait d'un seul
    // clic, sur une petite icone voisine de « Telecharger »: la base entiere
    // etait ecrasee par une archive parfois vieille de plusieurs semaines,
    // sans une question. On demande desormais une confirmation qui dit ce
    // qu'on remplace, et par quoi.
    if (!await _confirmerRestauration(row)) return;

    await _runBusyTask(() async {
      _forcePollingUntil = DateTime.now().add(const Duration(minutes: 2));
      _syncHistoryAutoRefresh();
      await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).post(
          '$base/$id/restore/',
          options: _backupRequestOptions(),
        ),
      );
      _showMessage('Restauration lancée en arrière-plan.', isSuccess: true);
      await _loadRows();
    });
  }

  /// Demande confirmation avant d'ecraser les donnees en place.
  Future<bool> _confirmerRestauration(Map<String, dynamic> row) async {
    final nom = row['filename']?.toString().isNotEmpty == true
        ? row['filename'].toString()
        : 'Archive #${row['id']}';
    final portee = _scopeLabel(row['scope']?.toString() ?? '');
    final datee = _dateLisible(row['created_at']);

    final reponse = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurer cette archive ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Les données actuelles seront remplacées par le contenu de '
              '$nom.',
            ),
            const SizedBox(height: 10),
            Text('Portée : $portee'),
            if (datee.isNotEmpty) Text('Sauvegardée le : $datee'),
            const SizedBox(height: 10),
            const Text(
              'Ce qui a été saisi depuis cette date sera perdu. '
              'L’opération ne s’annule pas.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirmer-restauration'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    return reponse == true;
  }

  Future<void> _pickRestoreFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    setState(() => _restoreFile = result.files.first);
  }

  Future<void> _uploadAndRestore() async {
    if (_restoreFile == null || _restoreFile!.bytes == null) {
      _showMessage('Sélectionnez un fichier ZIP.');
      return;
    }

    await _runBusyTask(() async {
      final selectedEtab = ref.read(etablissementProvider).selected;
      _forcePollingUntil = DateTime.now().add(const Duration(minutes: 2));
      _syncHistoryAutoRefresh();
      await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).post(
          '$base/upload-restore/',
          data: _buildRestoreFormData(selectedEtab),
          options: _backupRequestOptions(),
        ),
      );
      _showMessage('Archive envoyée. Restauration lancée en arrière-plan.', isSuccess: true);
      await _loadRows();
    });
  }

  FormData _buildRestoreFormData(Etablissement? selectedEtab) {
    return FormData.fromMap({
      'scope': _restoreScope,
      'notes': _restoreNotesController.text.trim(),
      if (_restoreScope == 'établissement' && selectedEtab != null)
        'etablissement_id': selectedEtab.id,
      'file': MultipartFile.fromBytes(
        _restoreFile!.bytes!,
        filename: _restoreFile!.name,
      ),
    });
  }

  Future<Response<dynamic>> _requestWithBackupFallback(
    Future<Response<dynamic>> Function(String base) request,
  ) async {
    DioException? last404;

    for (final base in _backupBases) {
      try {
        return await request(base);
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        if (statusCode == 404) {
          last404 = error;
          continue;
        }
        rethrow;
      }
    }

    if (last404 != null) {
      throw Exception(
        'Endpoint backup introuvable sur l\'API active. '
        'Vérifiez que le backend production est bien déployé.',
      );
    }

    throw Exception('Aucune route backup disponible.');
  }

  Future<void> _runBusyTask(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      _showMessage('Opération impossible: ${_extractOperationError(error)}');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Options _backupRequestOptions({ResponseType? responseType}) {
    return Options(
      connectTimeout: _backupConnectTimeout,
      sendTimeout: _backupTransferTimeout,
      receiveTimeout: _backupTransferTimeout,
      responseType: responseType,
    );
  }

  String _extractOperationError(Object error) {
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionTimeout) {
        return 'Connexion au serveur trop lente. Reessayez dans quelques instants.';
      }
      if (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'Opération longue interrompue par delai depasse. Reessayez.';
      }

      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return value.map((item) => item.toString()).join(' | ');
          }
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
      if (data is String && data.trim().isNotEmpty) {
        return data.trim();
      }

      final status = error.response?.statusCode;
      if (status != null) {
        return 'Erreur serveur HTTP $status.';
      }
      if ((error.message ?? '').trim().isNotEmpty) {
        return error.message!.trim();
      }
    }
    return error.toString();
  }

  Uint8List _toBytes(dynamic data) {
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    return Uint8List.fromList(List<int>.from(data as List));
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  /// L'historique restreint a ce qui est cherche, sur ce qui se lit a
  /// l'ecran: le nom de fichier, l'etablissement, la portee et le statut.
  List<Map<String, dynamic>> _archivesFiltrees() {
    final terme = _recherche.trim().toLowerCase();
    if (terme.isEmpty) return _rows;
    return _rows.where((row) {
      final champs = [
        row['filename']?.toString() ?? '',
        row['etablissement_name']?.toString() ?? '',
        row['status']?.toString() ?? '',
        _scopeLabel(row['scope']?.toString() ?? ''),
        row['notes']?.toString() ?? '',
      ];
      return champs.any((champ) => champ.toLowerCase().contains(terme));
    }).toList(growable: false);
  }

  /// Les trois reperes du module: combien d'archives, a quand remonte la
  /// derniere reussie, et ce qu'elles pesent en tout.
  Widget _compteurs(BuildContext context, String? etablissement) {
    final reussies = _rows
        .where((row) => row['status']?.toString() == 'completed')
        .toList(growable: false);
    final derniere = reussies.isEmpty ? '' : _dateLisible(reussies.first['created_at']);
    final volume = _rows.fold<int>(0, (somme, row) => somme + _octets(row));

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _compteur(context, Icons.inventory_2_outlined, '${_rows.length}',
            _rows.length > 1 ? 'archives' : 'archive'),
        _compteur(context, Icons.schedule_outlined,
            derniere.isEmpty ? 'jamais' : derniere, 'dernière sauvegarde'),
        _compteur(context, Icons.sd_storage_outlined,
            _tailleLisible(volume), 'stockées'),
        if (etablissement != null)
          _compteur(context, Icons.apartment_outlined, etablissement,
              'établissement actif'),
      ],
    );
  }

  Widget _compteur(
    BuildContext context,
    IconData icone,
    String valeur,
    String legende,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            valeur,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(legende, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  String _scopeLabel(String scope) {
    return scope == 'global' ? 'Globale plateforme' : 'Établissement';
  }

  /// « 29/08/2026 à 03:35 », vide si la date manque ou n'est pas lisible.
  String _dateLisible(Object? valeur) {
    final brut = valeur?.toString() ?? '';
    if (brut.isEmpty) return '';
    final date = DateTime.tryParse(brut)?.toLocal();
    if (date == null) return '';
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(date.day)}/${deux(date.month)}/${date.year} '
        'à ${deux(date.hour)}:${deux(date.minute)}';
  }

  /// La taille d'une archive dans l'unite ou elle se lit d'un coup d'oeil.
  /// Un nombre d'octets a sept chiffres ne dit rien a personne.
  String _tailleLisible(int octets) {
    if (octets <= 0) return '—';
    const unites = ['o', 'Ko', 'Mo', 'Go', 'To'];
    var valeur = octets.toDouble();
    var rang = 0;
    while (valeur >= 1024 && rang < unites.length - 1) {
      valeur /= 1024;
      rang += 1;
    }
    final arrondi = valeur >= 10 || rang == 0
        ? valeur.round().toString()
        : valeur.toStringAsFixed(1);
    return '$arrondi ${unites[rang]}';
  }

  int _octets(Map<String, dynamic> row) {
    final brut = row['file_size_bytes'];
    if (brut is int) return brut;
    return int.tryParse(brut?.toString() ?? '') ?? 0;
  }

  int _pourcentage(Object? brut) {
    final valeur = brut is int ? brut : int.tryParse(brut?.toString() ?? '');
    if (valeur == null || valeur < 0) return 0;
    return valeur > 100 ? 100 : valeur;
  }

  int _entier(Object? brut) {
    if (brut is int) return brut;
    if (brut is num) return brut.toInt();
    return int.tryParse(brut?.toString() ?? '') ?? 0;
  }

  /// L'avancement a montrer pour une ligne en cours.
  ///
  /// Une meme archive est d'abord ecrite, puis restauree plus tard: chaque
  /// operation a ses propres champs, sans quoi la restauration effacerait la
  /// trace de l'ecriture. `restore_phase` renseigne designe donc une
  /// restauration; vide, la ligne en est encore a s'ecrire.
  _Avancement _avancementDe(Map<String, dynamic> row) {
    final phaseRestauration = (row['restore_phase']?.toString() ?? '').trim();
    if (phaseRestauration.isNotEmpty) {
      return _Avancement(
        libelle: 'Restauration',
        pourcentage: _pourcentage(row['restore_progress']),
        phase: phaseRestauration,
        octetsFaits: 0,
        octetsTotal: 0,
        debut: null,
      );
    }

    return _Avancement(
      libelle: 'Sauvegarde',
      pourcentage: _pourcentage(row['build_progress']),
      phase: (row['build_phase']?.toString() ?? '').trim(),
      octetsFaits: _entier(row['bytes_done']),
      octetsTotal: _entier(row['bytes_total']),
      debut: DateTime.tryParse(row['build_started_at']?.toString() ?? '')?.toLocal(),
    );
  }

  /// « 3,2 Mo sur 7,4 Mo », vide tant que le volume n'est pas connu.
  String _volumeTraite(_Avancement avancement) {
    if (avancement.octetsTotal <= 0) return '';
    return '${_tailleLisible(avancement.octetsFaits)} '
        'sur ${_tailleLisible(avancement.octetsTotal)}';
  }

  /// Le temps qu'il reste, deduit du debit constate depuis le depart.
  ///
  /// Vide tant qu'il n'y a pas de quoi l'estimer: une duree annoncee sur
  /// deux octets ecrits serait une invention, et l'ecran passerait son temps
  /// a se dedire.
  String _resteAFaire(_Avancement avancement) {
    final debut = avancement.debut;
    if (debut == null || avancement.octetsTotal <= 0) return '';
    final restant = avancement.octetsTotal - avancement.octetsFaits;
    if (restant <= 0) return '';

    final ecoule = DateTime.now().difference(debut).inMilliseconds;
    if (ecoule < 1500 || avancement.octetsFaits <= 0) return '';

    final octetsParSeconde = avancement.octetsFaits * 1000 / ecoule;
    if (octetsParSeconde <= 0) return '';

    final secondes = (restant / octetsParSeconde).round();
    if (secondes < 5) return 'reste quelques secondes';
    if (secondes < 60) return 'reste ~$secondes s';
    final minutes = (secondes / 60).round();
    if (minutes < 60) return 'reste ~$minutes min';
    final heures = (minutes / 60).round();
    return 'reste ~$heures h';
  }

  @override
  Widget build(BuildContext context) {
    final selectedEtab = ref.watch(etablissementProvider).selected;
    // Restaurer ecrase la base: la matrice reserve l'ecriture au super
    // admin, la direction reste en lecture.
    final isSuperAdmin = ref
        .watch(currentPermissionsProvider)
        .canWrite('backup_restore');

    if (_loading) {
      return RefreshIndicator(
        onRefresh: _loadRows,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 420,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    final archivesAffichees = _archivesFiltrees();

    return RefreshIndicator(
      onRefresh: _loadRows,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Sauvegarde & Restauration',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Archives de la plateforme et des établissements, restauration '
            'et suivi des opérations.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          // Les memes reperes chiffres que les autres modules: sans eux,
          // savoir a quand remonte la derniere sauvegarde demandait de lire
          // l'historique ligne a ligne.
          _compteurs(context, selectedEtab?.name),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Créer une sauvegarde',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  // Ce que l'archive emporte, dit a l'endroit ou on le
                  // choisit. Sans cette phrase, « inclure les medias » se
                  // cochait sans savoir ce que le reste contenait deja.
                  Text(
                    'L\'archive contient toutes les données saisies : élèves, '
                    'notes, absences, paiements, personnel, comptes. '
                    'Ni le code de l\'application, ni les mots de passe en '
                    'clair, ni les réglages du serveur.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _createScope,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      if (isSuperAdmin)
                        const DropdownMenuItem(
                          value: 'global',
                          child: Text('Sauvegarde globale plateforme'),
                        ),
                      const DropdownMenuItem(
                        value: 'établissement',
                        child: Text('Sauvegarde de l\'établissement actif'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _createScope = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _includeMedia,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inclure les médias'),
                    subtitle: Text(
                      _volumes == null
                          ? 'Photos, logos, pièces jointes, justificatifs.'
                          : 'Photos, logos, pièces jointes, justificatifs : '
                                '${_tailleLisible(_volume('media_hors_bibliotheque_octets'))}.',
                    ),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _includeMedia = value),
                  ),
                  // La case decisive: sans elle, la sauvegarde emportait tout
                  // le fonds d'annales a chaque fois, pour un volume sans
                  // rapport avec ce qu'une ecole a reellement saisi.
                  SwitchListTile(
                    key: const Key('inclure-bibliotheque'),
                    value: _includeMedia && _includeLibrary,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inclure les documents de bibliothèque'),
                    subtitle: Text(
                      _volumes == null
                          ? 'Annales et manuels importés. Alourdit fortement '
                                'l\'archive, et se réimportent sans perte.'
                          : 'Annales et manuels importés : '
                                '${_tailleLisible(_volume('bibliotheque_octets'))}. '
                                'Se réimportent sans perte.',
                    ),
                    onChanged: _busy || !_includeMedia
                        ? null
                        : (value) => setState(() => _includeLibrary = value),
                  ),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optionnel)',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createBackup,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Lancer la sauvegarde'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload + restauration',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _restoreScope,
                    decoration: const InputDecoration(labelText: 'Mode restauration'),
                    items: [
                      if (isSuperAdmin)
                        const DropdownMenuItem(
                          value: 'global',
                          child: Text('Restauration globale plateforme'),
                        ),
                      const DropdownMenuItem(
                        value: 'établissement',
                        child: Text('Restauration établissement actif'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _restoreScope = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickRestoreFile,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Choisir ZIP'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _restoreFile?.name ?? 'Aucun fichier sélectionné',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _restoreNotesController,
                    decoration: const InputDecoration(labelText: 'Notes (optionnel)'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _uploadAndRestore,
                    icon: const Icon(Icons.restore_page_outlined),
                    label: const Text('Uploader et restaurer'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Historique',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (isSuperAdmin && _rows.length > 1)
                TextButton.icon(
                  key: const Key('nettoyer-historique'),
                  onPressed: _busy ? null : _nettoyerLHistorique,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Nettoyer'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          BarreRechercheModule(
            controller: _rechercheController,
            indication:
                'Rechercher une archive : nom de fichier, établissement, '
                'statut…',
            onChanged: (valeur) => setState(() => _recherche = valeur),
            onEffacer: () {
              _rechercheController.clear();
              setState(() => _recherche = '');
            },
            compact: MediaQuery.sizeOf(context).width < 720,
          ),
          const SizedBox(height: 10),
          if (archivesAffichees.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _rows.isEmpty
                      ? 'Aucune archive disponible.'
                      : 'Aucune archive ne correspond à « $_recherche ».',
                ),
              ),
            )
          else
            ...archivesAffichees.map((row) {
              final statusValue = row['status']?.toString() ?? '-';
              final canDownload = (row['file_path']?.toString().isNotEmpty ?? false);
              final restoreLog = (row['restore_log']?.toString() ?? '').trim();
              final isFailed = statusValue == 'failed';
              final isRunning = statusValue == 'running' || statusValue == 'pending';
              final avancement = _avancementDe(row);
              final volumeTraite = _volumeTraite(avancement);
              final reste = _resteAFaire(avancement);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row['filename']?.toString().isNotEmpty == true
                                  ? row['filename'].toString()
                                  : 'Archive #${row['id']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (canDownload)
                            IconButton(
                              tooltip: 'Télécharger',
                              onPressed: _busy ? null : () => _downloadBackup(row),
                              icon: const Icon(Icons.download_outlined),
                            ),
                          IconButton(
                            tooltip: 'Restaurer',
                            onPressed: _busy ? null : () => _restoreFromArchive(row),
                            icon: const Icon(Icons.settings_backup_restore_outlined),
                          ),
                          if (isSuperAdmin)
                            IconButton(
                              tooltip: 'Supprimer',
                              // Rien a supprimer tant que le fichier s'ecrit:
                              // l'archive serait tronquee et la ligne
                              // reclamerait un fichier disparu.
                              onPressed: _busy || isRunning
                                  ? null
                                  : () => _supprimerArchive(row),
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                      Text(
                        '${_scopeLabel(row['scope']?.toString() ?? '')} • Statut: $statusValue',
                      ),
                      if (isRunning) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: avancement.pourcentage / 100.0,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${avancement.pourcentage}%',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            avancement.libelle,
                            if (avancement.phase.isNotEmpty) avancement.phase,
                            if (volumeTraite.isNotEmpty) volumeTraite,
                            if (reste.isNotEmpty) reste,
                          ].join(' • '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (isFailed && restoreLog.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Erreur: ${restoreLog.split("\n").first}'),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Ce que l'ecran a besoin de savoir d'une operation en cours.
class _Avancement {
  const _Avancement({
    required this.libelle,
    required this.pourcentage,
    required this.phase,
    required this.octetsFaits,
    required this.octetsTotal,
    required this.debut,
  });

  final String libelle;
  final int pourcentage;
  final String phase;
  final int octetsFaits;
  final int octetsTotal;
  final DateTime? debut;
}
