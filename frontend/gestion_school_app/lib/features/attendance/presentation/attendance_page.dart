import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/permissions/module_permissions.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/attendance_stats.dart';
import '../domain/attendance_student.dart';
import 'attendance_controller.dart';
import 'widgets/attendance_dashboard_card.dart';
import 'widgets/attendance_sheet_journal.dart';
import 'widgets/attendance_sheet_list.dart';

/// Ce qu'on fait d'un justificatif deja joint.
enum _ActionJustificatif { remplacer, retirer }

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  final _conduiteController = TextEditingController(text: '18');
  final _rechercheEleveController = TextEditingController();

  int? _selectedStudentId;
  String _rechercheEleve = '';
  bool _conduiteSaving = false;
  bool _sheetLoading = false;
  bool _sheetSaving = false;
  List<Map<String, dynamic>> _sheetClassrooms = [];
  List<Map<String, dynamic>> _sheetItems = [];
  int? _sheetSelectedClassroomId;
  DateTime _sheetSelectedDate = DateTime.now();
  bool _sheetLocked = false;
  String _sheetValidatedByName = '';
  String? _sheetValidatedAt;

  bool _sheetBootstrapped = false;

  List<Map<String, dynamic>> _journalFiches = const [];
  bool _journalLoading = false;

  /// Horodatage du dernier chargement de la fiche, affiche en en-tete comme
  /// sur les deux autres modules: une page sans indication de fraicheur se
  /// lit comme un ecran fige.
  DateTime? _dernierChargement;

  /// Qui note la conduite.
  ///
  /// Seule regle de cette page qui reste exprimee en roles: la conduite est
  /// un champ de l'eleve, pas un module, et la matrice de droits n'a pas de
  /// cle pour elle. La verite reste cote serveur -- StudentSerializer refuse
  /// l'ecriture aux autres profils -- et cette liste ne fait que griser un
  /// champ que le serveur rejetterait.
  static const _rolesConduite = {'censor', 'supervisor', 'super_admin'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sheetBootstrapped) {
        return;
      }
      if (_peutVoirLaFiche(ref.read(currentPermissionsProvider))) {
        _sheetBootstrapped = true;
        _loadSheetClassrooms();
        _loadSheetJournal();
      }
    });
  }

  @override
  void dispose() {
    _conduiteController.dispose();
    _rechercheEleveController.dispose();
    super.dispose();
  }

  /// La feuille d'appel decrit une classe, pas un eleve.
  ///
  /// Le parent et l'eleve lisent l'assiduite en portee restreinte (leurs
  /// enfants, soi): la vue par classe ne sait pas restreindre cela et n'aurait
  /// pas de sens pour eux -- ils ont leur propre ecran. L'enseignant est
  /// restreint lui aussi, mais a des classes, et il ecrit: c'est ce qui l'en
  /// distingue. Meme regle que _assert_sheet_scope cote serveur.
  static bool _peutVoirLaFiche(ModulePermissions droits) {
    final acces = droits.of('attendance');
    return acces.canRead && (acces.canWrite || !acces.scoped);
  }

  /// Cloturer engage la classe entiere: l'enseignant saisit mais ne verrouille
  /// pas. Ecriture sans portee restreinte, comme cote serveur.
  static bool _peutValiderLaFiche(ModulePermissions droits) {
    final acces = droits.of('attendance');
    return acces.canWrite && !acces.scoped;
  }

  Future<void> _loadSheetClassrooms() async {
    setState(() {
      _sheetLoading = true;
    });
    try {
      final rows = await ref.read(attendanceRepositoryProvider).fetchSheetClassrooms();
      if (!mounted) {
        return;
      }
      setState(() {
        _sheetClassrooms = rows;
        if (_sheetClassrooms.isEmpty) {
          _sheetSelectedClassroomId = null;
          _sheetItems = [];
          _sheetLocked = false;
          _sheetValidatedByName = '';
          _sheetValidatedAt = null;
        } else {
          final exists = _sheetClassrooms.any(
            (row) => _asInt(row['id']) == _sheetSelectedClassroomId,
          );
          if (!exists) {
            _sheetSelectedClassroomId = _asInt(_sheetClassrooms.first['id']);
          }
        }
      });
      if (_sheetSelectedClassroomId != null) {
        await _loadClassSheet();
      }
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur chargement classes (fiche).'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetLoading = false;
        });
      }
    }
  }

  /// Fiches deja enregistrees, toutes classes accessibles confondues.
  ///
  /// Volontairement non filtre sur la classe selectionnee: on vient ici pour
  /// retrouver une fiche, souvent d'une autre classe que celle affichee.
  Future<void> _loadSheetJournal() async {
    setState(() => _journalLoading = true);
    try {
      final fiches = await ref
          .read(attendanceRepositoryProvider)
          .fetchSheetJournal();
      if (!mounted) return;
      setState(() => _journalFiches = fiches);
    } catch (error) {
      // Un journal indisponible ne doit pas empecher de faire l'appel: la
      // feuille est au-dessus et fonctionne sans lui.
      _showMessage(
        _sheetErrorMessage(error, fallback: 'Erreur chargement des fiches.'),
      );
    } finally {
      if (mounted) setState(() => _journalLoading = false);
    }
  }

  /// Exporte une fiche du journal.
  ///
  /// Elle est d'abord chargee dans le formulaire au-dessus, puis on reutilise
  /// les exports existants: ecrire un second chemin d'export ferait deux
  /// facons de produire le meme document, qui divergeraient.
  Future<void> _exportSheetAt(
    int classroomId,
    String date, {
    required bool excel,
  }) async {
    setState(() {
      _sheetSelectedClassroomId = classroomId;
      _sheetSelectedDate = DateTime.tryParse(date) ?? _sheetSelectedDate;
    });
    await _loadClassSheet();
    if (!mounted) return;
    if (excel) {
      await _exportClassSheetExcel();
    } else {
      await _exportClassSheetPdf();
    }
  }

  Future<void> _loadClassSheet() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      return;
    }
    setState(() {
      _sheetLoading = true;
    });
    try {
      final payload = await ref
          .read(attendanceRepositoryProvider)
          .fetchClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
          );
      if (!mounted) {
        return;
      }
      final rowsRaw = payload['items'];
      final rows = rowsRaw is List
          ? rowsRaw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _sheetItems = rows;
        _sheetLocked = payload['is_locked'] == true;
        _sheetValidatedByName = payload['validated_by_name']?.toString() ?? '';
        _sheetValidatedAt = payload['validated_at']?.toString();
        _dernierChargement = DateTime.now();
      });
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur chargement fiche.'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetLoading = false;
        });
      }
    }
  }

  Future<void> _saveClassSheet() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }
    setState(() {
      _sheetSaving = true;
    });
    try {
      final items = _sheetItems
          .map(
            (row) => {
              'student': row['student'],
              'is_absent': row['is_absent'] == true,
              'is_late': row['is_late'] == true,
              'reason': (row['reason'] ?? '').toString(),
            },
          )
          .toList(growable: false);
      final result = await ref
          .read(attendanceRepositoryProvider)
          .saveClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            items: items,
          );
      if (!mounted) {
        return;
      }
      _showMessage(
        result['detail']?.toString() ?? 'Fiche de présence enregistrée.',
        isSuccess: true,
      );
      ref.invalidate(attendancesProvider);
      ref.invalidate(attendanceMonthlyStatsProvider);
      await _loadClassSheet();
      // La fiche qu'on vient d'enregistrer doit apparaitre au journal.
      await _loadSheetJournal();
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur enregistrement fiche.'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetSaving = false;
        });
      }
    }
  }

  Future<void> _setClassSheetLock(bool lock) async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }

    setState(() {
      _sheetSaving = true;
    });
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .setClassSheetLock(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            lock: lock,
          );

      if (!mounted) {
        return;
      }
      _showMessage(
        result['detail']?.toString() ??
            (lock ? 'Fiche validée.' : 'Fiche déverrouillée.'),
        isSuccess: true,
      );
      await _loadClassSheet();
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur validation fiche.'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetSaving = false;
        });
      }
    }
  }

  Future<void> _exportClassSheetPdf() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }
    try {
      final bytes = await ref
          .read(attendanceRepositoryProvider)
          .exportClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            format: 'pdf',
          );
      if (bytes.isEmpty) {
        _showMessage('Export PDF vide.');
        return;
      }
      await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(bytes),
      );
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur export PDF.'));
    }
  }

  Future<void> _exportClassSheetExcel() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }
    try {
      final bytes = await ref
          .read(attendanceRepositoryProvider)
          .exportClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            format: 'xlsx',
          );
      if (bytes.isEmpty) {
        _showMessage('Export Excel vide.');
        return;
      }

      final fileName =
          'presence_classe_${_sheetSelectedClassroomId}_${_apiDate(_sheetSelectedDate)}.xlsx';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la fiche Excel',
        fileName: fileName,
      );

      if (savePath == null) {
        if (!mounted) {
          return;
        }
        _showMessage('Export Excel prêt (${bytes.length} octets).', isSuccess: true);
        return;
      }

      final file = File(savePath);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        return;
      }
      _showMessage('Fichier Excel exporté.', isSuccess: true);
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur export Excel.'));
    }
  }

  /// Le justificatif d'une absence: deposer, remplacer, retirer.
  ///
  /// Le champ existait en base depuis l'origine et les statistiques
  /// mensuelles comptaient deja les justificatifs, mais aucun ecran ne
  /// permettait d'en deposer un: le compteur affichait zero en permanence.
  ///
  /// Une piece deja jointe ouvre un choix plutot que d'ecraser en silence:
  /// se tromper de fichier ne doit pas etre un aller sans retour.
  Future<void> _ouvrirJustificatif(Map<String, dynamic> ligne) async {
    final attendanceId = AttendanceSheetList.identifiant(ligne);
    if (attendanceId == null) {
      _showMessage('Enregistrez la fiche avant de joindre un justificatif.');
      return;
    }

    if (AttendanceSheetList.estJustifie(ligne)) {
      // Retirer demande le niveau administration, comme cote serveur: le
      // proposer a qui recevra un 403 ne ferait qu'egarer.
      final peutRetirer = ref
          .read(currentPermissionsProvider)
          .of('attendance')
          .canDelete;
      final action = await _choisirActionJustificatif(ligne, peutRetirer);
      if (action == null) return;
      if (action == _ActionJustificatif.retirer) {
        await _retirerJustificatif(ligne, attendanceId);
        return;
      }
    }

    await _deposerJustificatif(ligne, attendanceId);
  }

  /// Que faire de la piece deja jointe.
  Future<_ActionJustificatif?> _choisirActionJustificatif(
    Map<String, dynamic> ligne,
    bool peutRetirer,
  ) {
    final nom = (ligne['proof_name'] ?? '').toString();
    return showDialog<_ActionJustificatif>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Justificatif joint'),
        content: Text(
          nom.isEmpty
              ? 'Une pièce est déjà jointe à cette absence.'
              : 'Pièce jointe: $nom',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          if (peutRetirer)
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_ActionJustificatif.retirer),
              child: const Text('Retirer'),
            ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_ActionJustificatif.remplacer),
            child: const Text('Remplacer'),
          ),
        ],
      ),
    );
  }

  Future<void> _retirerJustificatif(
    Map<String, dynamic> ligne,
    int attendanceId,
  ) async {
    setState(() => _sheetSaving = true);
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .removeProof(attendanceId: attendanceId);
      if (!mounted) return;
      setState(() {
        ligne['has_proof'] = false;
        ligne['proof_name'] = '';
        ligne['proof_url'] = '';
      });
      _showMessage('Justificatif retiré.', isSuccess: true);
      ref.invalidate(attendanceMonthlyStatsProvider);
    } catch (error) {
      _showMessage(
        _sheetErrorMessage(error, fallback: 'Erreur retrait du justificatif.'),
      );
    } finally {
      if (mounted) setState(() => _sheetSaving = false);
    }
  }

  Future<void> _deposerJustificatif(
    Map<String, dynamic> ligne,
    int attendanceId,
  ) async {
    final choix = await FilePicker.platform.pickFiles(
      dialogTitle: 'Justificatif d’absence',
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic'],
    );
    if (choix == null || choix.files.isEmpty) return;
    final fichier = choix.files.first;

    // Le web ne donne jamais de chemin: seul `bytes` est disponible partout.
    final octets = fichier.bytes;
    if (octets == null) {
      _showMessage('Fichier illisible.');
      return;
    }

    setState(() => _sheetSaving = true);
    try {
      final resultat = await ref
          .read(attendanceRepositoryProvider)
          .uploadProof(
            attendanceId: attendanceId,
            fileName: fichier.name,
            bytes: octets,
          );
      if (!mounted) return;
      setState(() {
        ligne['has_proof'] = true;
        ligne['proof_name'] = resultat['proof_name'] ?? fichier.name;
        ligne['proof_url'] = resultat['proof_url'] ?? '';
      });
      _showMessage('Justificatif enregistré.', isSuccess: true);
      // Le compteur « Justificatifs » de l'en-tete vient du serveur.
      ref.invalidate(attendanceMonthlyStatsProvider);
    } catch (error) {
      _showMessage(
        _sheetErrorMessage(error, fallback: 'Erreur dépôt du justificatif.'),
      );
    } finally {
      if (mounted) setState(() => _sheetSaving = false);
    }
  }

  String _sheetErrorMessage(Object error, {required String fallback}) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 404) {
        return 'L\'API utilisée ne contient pas encore la fiche de présence par classe. '
            'Redémarre le backend local ou reconfigure l\'URL API vers le serveur mis à jour.';
      }

      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail']?.toString().trim();
        if (detail != null && detail.isNotEmpty) {
          return detail;
        }
      }
    }
    return '$fallback ${error.toString()}';
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    const successColor = Color(0xFF197A43);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? successColor : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(attendanceStudentsProvider);
    final statsAsync = ref.watch(attendanceMonthlyStatsProvider);
    final stats = statsAsync.valueOrNull;
    final authState = ref.watch(authControllerProvider);
    final droits = ref.watch(currentPermissionsProvider);
    final acces = droits.of('attendance');

    final userRole = authState.valueOrNull?.role;
    final canEditConduite =
        userRole != null && _rolesConduite.contains(userRole);
    final canUseSheet = _peutVoirLaFiche(droits);
    final canWriteSheet = acces.canWrite;
    final canValidateSheet = _peutValiderLaFiche(droits);
    // Un profil restreint a l'ecriture voit ses propres classes: c'est le
    // serveur qui borne la liste, on s'y aligne plutot que de nommer un role.
    final isScopedWriter = acces.canWrite && acces.scoped;
    final allowedClassroomIds = isScopedWriter
        ? _sheetClassrooms
              .map((row) => _asInt(row['id']))
              .where((id) => id > 0)
              .toSet()
        : <int>{};

    return Scaffold(
      // Le titre vit desormais dans l'onglet « Élèves » du module Émargements:
      // une barre de plus repeterait ce que la navigation dit deja.
      appBar: null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AttendanceDashboardCard(
            stats: stats,
            statsError: statsAsync.hasError
                ? 'Statistiques du mois indisponibles: ${statsAsync.error}'
                : null,
            classCount: _sheetClassrooms.length,
            scopeLabel: _libelleEtablissement(authState.valueOrNull),
            refreshLabel: _libelleFraicheur(),
            isCompactLayout: MediaQuery.sizeOf(context).width < 1100,
            loading: statsAsync.isLoading || _sheetLoading,
            readOnly: canUseSheet && !canWriteSheet,
            onRefresh: _toutRecharger,
            courbe: stats == null ? null : _courbeDuMois(context, stats),
          ),
          if (isScopedWriter)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Périmètre restreint: classes et élèves de vos affectations.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          if (canUseSheet)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Fiche de présence par classe',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    // Couleurs du theme et non figees: l'orange pale d'avant
                    // rendait ce bandeau illisible en theme sombre.
                    if (_sheetLocked)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .tertiaryContainer
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Fiche verrouillée'
                                '${_sheetValidatedByName.isNotEmpty ? ' • par $_sheetValidatedByName' : ''}'
                                '${_sheetValidatedAt != null ? ' • $_sheetValidatedAt' : ''}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_sheetLocked) const SizedBox(height: 10),
                    if (_sheetLoading) const LinearProgressIndicator(),
                    if (_sheetClassrooms.isEmpty && !_sheetLoading)
                      const Text('Aucune classe accessible pour cette fiche.'),
                    if (_sheetClassrooms.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        initialValue: _sheetSelectedClassroomId,
                        decoration: const InputDecoration(labelText: 'Classe'),
                        items: _sheetClassrooms
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: _asInt(row['id']),
                                child: Text(
                                  '${row['name'] ?? '-'}'
                                  '${(row['academic_year_name']?.toString().isNotEmpty ?? false) ? ' • ${row['academic_year_name']}' : ''}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _sheetLoading
                            ? null
                            : (value) async {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _sheetSelectedClassroomId = value;
                                });
                                await _loadClassSheet();
                              },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Date de la fiche'),
                        subtitle: Text(_formatDate(_sheetSelectedDate)),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_month),
                          onPressed: _sheetLoading
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _sheetSelectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _sheetSelectedDate = picked;
                                    });
                                    await _loadClassSheet();
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_sheetItems.isEmpty && !_sheetLoading)
                        const Text('Aucun élève trouvé pour cette classe/date.')
                      else
                        AttendanceSheetList(
                          items: _sheetItems,
                          editable: canWriteSheet && !_sheetLocked,
                          onPresenceChanged: (row, etat) => setState(() {
                            final absent = etat == PresenceEleve.absent;
                            row['is_absent'] = absent;
                            // Repasser present efface le motif: il decrivait
                            // une absence qui n'existe plus, et il serait
                            // enregistre tel quel.
                            if (!absent) row['reason'] = '';
                          }),
                          onRetardChanged: (row, enRetard) =>
                              setState(() => row['is_late'] = enRetard),
                          onMotifChanged: (row, motif) => row['reason'] = motif,
                          onToutPresent: () => setState(() {
                            for (final row in _sheetItems) {
                              row['is_absent'] = false;
                              row['reason'] = '';
                            }
                          }),
                          // Le depot reste ouvert sur une fiche verrouillee:
                          // le mot d'excuse arrive le lendemain, apres la
                          // validation du jour.
                          onJustificatif: canWriteSheet
                              ? _ouvrirJustificatif
                              : null,
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _sheetLoading ? null : _exportClassSheetPdf,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Export PDF'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _sheetLoading ? null : _exportClassSheetExcel,
                              icon: const Icon(Icons.table_view_outlined),
                              label: const Text('Export Excel'),
                            ),
                            if (canValidateSheet)
                              OutlinedButton.icon(
                                onPressed: (_sheetSaving || _sheetLoading)
                                    ? null
                                    : () => _setClassSheetLock(!_sheetLocked),
                                icon: Icon(
                                  _sheetLocked
                                      ? Icons.lock_open_outlined
                                      : Icons.verified_outlined,
                                ),
                                label: Text(
                                  _sheetLocked
                                      ? 'Déverrouiller'
                                      : 'Valider & verrouiller',
                                ),
                              ),
                            FilledButton.icon(
                              onPressed: (!canWriteSheet ||
                                      _sheetSaving ||
                                      _sheetLoading ||
                                      _sheetLocked)
                                  ? null
                                  : _saveClassSheet,
                              icon: _sheetSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('Enregistrer la fiche'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (canUseSheet) const SizedBox(height: 16),
          // Ce qui reste de l'ancienne « Saisie absence/retard »: la
          // conduite, seule chose que la feuille d'appel ne sait pas dire.
          // Le reste du formulaire redisait la feuille en moins bien, et
          // echouait des qu'elle etait enregistree -- une seule presence par
          // eleve et par date, ce que la saisie unitaire ignorait.
          if (canEditConduite)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Note de conduite',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Absences et retards se saisissent dans la feuille d’appel ci-dessus.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    studentsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('Erreur élèves: $error'),
                      data: (students) {
                        final perimetre = isScopedWriter
                            ? students
                                  .where(
                                    (student) =>
                                        student.classroomId != null &&
                                        allowedClassroomIds.contains(
                                          student.classroomId,
                                        ),
                                  )
                                  .toList(growable: false)
                            : students;

                        if (perimetre.isEmpty) {
                          return const Text('Aucun élève disponible');
                        }
                        return _selecteurEleve(context, perimetre);
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 150,
                          child: TextFormField(
                            controller: _conduiteController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            decoration: const InputDecoration(
                              labelText: 'Conduite (/20)',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: (_conduiteSaving || _selectedStudentId == null)
                              ? null
                              : _enregistrerConduite,
                          icon: _conduiteSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Enregistrer la conduite'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Fiches enregistrées',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Les fiches déjà saisies, par classe et par date.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          AttendanceSheetJournal(
            fiches: _journalFiches,
            loading: _journalLoading,
            onVoir: (classroomId, date) {
              // Recharger dans le formulaire au-dessus plutot que d'ouvrir un
              // second ecran: c'est le meme document, verrouille ou non.
              setState(() {
                _sheetSelectedClassroomId = classroomId;
                _sheetSelectedDate =
                    DateTime.tryParse(date) ?? _sheetSelectedDate;
              });
              _loadClassSheet();
            },
            onExporterPdf: (classroomId, date) =>
                _exportSheetAt(classroomId, date, excel: false),
            onExporterExcel: (classroomId, date) =>
                _exportSheetAt(classroomId, date, excel: true),
          ),
        ],
      ),
    );
  }

  /// Courbe du mois, lisible: deux series de meme couleur sans legende ne
  /// disaient pas laquelle etait « absences ».
  Widget _courbeDuMois(BuildContext context, AttendanceMonthlyStats stats) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (stats.daily.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            'Aucun enregistrement ce mois-ci.',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    Widget legende(String libelle, Color couleur) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
              color: couleur,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(libelle, style: textTheme.labelSmall),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          children: [
            legende('Absences', scheme.error),
            legende('Retards', scheme.tertiary),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 28),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    // Trente etiquettes se chevauchent: on n'en garde qu'une
                    // sur cinq, et seulement le quantieme.
                    interval: (stats.daily.length / 5).ceilToDouble(),
                    getTitlesWidget: (valeur, meta) {
                      final index = valeur.round();
                      if (index < 0 || index >= stats.daily.length) {
                        return const SizedBox.shrink();
                      }
                      final jour = DateTime.tryParse(stats.daily[index].date);
                      return Text(
                        jour == null ? '' : '${jour.day}',
                        style: textTheme.labelSmall,
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                _serie(
                  [for (final jour in stats.daily) jour.absences],
                  scheme.error,
                ),
                _serie(
                  [for (final jour in stats.daily) jour.lates],
                  scheme.tertiary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _serie(List<int> valeurs, Color couleur) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < valeurs.length; i++)
          FlSpot(i.toDouble(), valeurs[i].toDouble()),
      ],
      isCurved: true,
      color: couleur,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }

  /// Etablissement dont on regarde l'emargement, comme l'affichent « Gestion
  /// des eleves » et « Enseignants ».
  String _libelleEtablissement(AuthUser? utilisateur) {
    final nom = utilisateur?.etablissementName.trim() ?? '';
    if (nom.isNotEmpty) return nom;
    return utilisateur?.role == 'super_admin'
        ? 'Aucun établissement actif'
        : 'Établissement utilisateur';
  }

  String _libelleFraicheur() {
    final instant = _dernierChargement;
    if (instant == null) return 'Maj: -';
    final heures = instant.hour.toString().padLeft(2, '0');
    final minutes = instant.minute.toString().padLeft(2, '0');
    return 'Maj: $heures:$minutes';
  }

  /// Recharge tout ce que la page montre, d'un seul geste.
  Future<void> _toutRecharger() async {
    ref.invalidate(attendanceMonthlyStatsProvider);
    ref.invalidate(attendanceStudentsProvider);
    await _loadSheetClassrooms();
    await _loadSheetJournal();
  }

  /// Selecteur d'eleve filtre par la saisie.
  ///
  /// Un menu deroulant listait l'etablissement entier: inutilisable au-dela
  /// de cent eleves, et la page etait la seule des trois a ne proposer aucune
  /// recherche.
  Widget _selecteurEleve(
    BuildContext context,
    List<AttendanceStudent> eleves,
  ) {
    final saisie = _rechercheEleve.trim().toLowerCase();
    final correspondances = saisie.isEmpty
        ? eleves
        : eleves
              .where(
                (eleve) =>
                    eleve.fullName.toLowerCase().contains(saisie) ||
                    eleve.matricule.toLowerCase().contains(saisie),
              )
              .toList(growable: false);

    final selectionValide =
        _selectedStudentId != null &&
        correspondances.any((eleve) => eleve.id == _selectedStudentId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _rechercheEleveController,
          decoration: InputDecoration(
            labelText: 'Rechercher un élève',
            hintText: 'Nom ou matricule',
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            border: const OutlineInputBorder(),
            suffixIcon: _rechercheEleve.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _rechercheEleveController.clear();
                      setState(() => _rechercheEleve = '');
                    },
                  ),
          ),
          onChanged: (valeur) => setState(() => _rechercheEleve = valeur),
        ),
        const SizedBox(height: 10),
        if (correspondances.isEmpty)
          Text(
            'Aucun élève ne correspond à « $_rechercheEleve ».',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          DropdownButtonFormField<int>(
            initialValue: selectionValide ? _selectedStudentId : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Élève',
              isDense: true,
              border: const OutlineInputBorder(),
              helperText: saisie.isEmpty
                  ? null
                  : '${correspondances.length} résultat'
                        '${correspondances.length > 1 ? 's' : ''}',
            ),
            // Un menu de mille lignes ne se parcourt pas: la recherche
            // au-dessus est le chemin, celui-ci confirme le choix.
            items: correspondances
                .take(50)
                .map(
                  (eleve) => DropdownMenuItem<int>(
                    value: eleve.id,
                    child: Text(
                      '${eleve.fullName} (${eleve.matricule})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (valeur) => setState(() => _selectedStudentId = valeur),
          ),
      ],
    );
  }

  Future<void> _enregistrerConduite() async {
    final studentId = _selectedStudentId;
    if (studentId == null) {
      _showMessage('Sélectionnez un élève.');
      return;
    }

    final note = double.tryParse(
      _conduiteController.text.trim().replaceAll(',', '.'),
    );
    if (note == null || note < 0 || note > 20) {
      _showMessage('La conduite doit être comprise entre 0 et 20.');
      return;
    }

    setState(() => _conduiteSaving = true);
    try {
      await ref
          .read(attendanceRepositoryProvider)
          .saveConduite(studentId: studentId, conduite: note);
      if (!mounted) return;
      _showMessage('Conduite enregistrée.', isSuccess: true);
    } catch (error) {
      _showMessage(
        _sheetErrorMessage(error, fallback: 'Erreur enregistrement conduite.'),
      );
    } finally {
      if (mounted) setState(() => _conduiteSaving = false);
    }
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _apiDate(DateTime value) => _formatDate(value);

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
