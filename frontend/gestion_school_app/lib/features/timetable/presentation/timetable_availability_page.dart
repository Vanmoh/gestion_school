import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/permissions/module_permissions.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/availability_repository.dart';
import '../domain/availability.dart';
import 'widgets/availability_grid_view.dart';
import 'widgets/campaign_banner.dart';
import 'widgets/campaign_responses_dialog.dart';

/// La collecte des disponibilités, avant que le planning n'existe.
///
/// L'écran décrivait auparavant une réservation exclusive — « un créneau
/// réservé devient indisponible pour les autres » — et l'unicité en base
/// allait dans le même sens : le premier enseignant à déclarer son lundi
/// matin en devenait propriétaire pour toute l'école, et les suivants
/// échouaient. Une disponibilité se partage, c'est même sa raison d'être :
/// dix professeurs libres le lundi à huit heures, c'est exactement ce que
/// l'administration a besoin de savoir pour arbitrer.
class TeacherAvailabilityPage extends ConsumerStatefulWidget {
  const TeacherAvailabilityPage({super.key});

  @override
  ConsumerState<TeacherAvailabilityPage> createState() =>
      _TeacherAvailabilityPageState();
}

class _TeacherAvailabilityPageState
    extends ConsumerState<TeacherAvailabilityPage> {
  bool _chargement = true;
  bool _enCours = false;
  String? _erreur;

  AvailabilityGrid _grille = AvailabilityGrid.vide;
  AvailabilityCampaign? _campagne;
  List<Map<String, dynamic>> _enseignants = const [];
  int? _enseignantVise;
  bool _dejaRendu = false;

  /// Vrai quand l'écran sert à déclarer, faux quand il sert à arbitrer.
  /// L'enseignant n'a pas le choix ; l'administration bascule.
  bool _modeDeclaration = false;

  // Bornes de la journee scolaire, larges a dessein: mieux vaut une case
  // vide de trop qu'un creneau que personne ne peut declarer.
  final int _heureDebut = 7;
  final int _heureFin = 18;
  int _pas = 60;

  bool get _estEnseignant =>
      ref.read(authControllerProvider).value?.role == 'teacher';

  bool get _peutEcrire =>
      ref.read(currentPermissionsProvider).canWrite('teacher_availability');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final depot = ref.read(availabilityRepositoryProvider);
      final enseignants = await _chargerLesEnseignants();
      final user = ref.read(authControllerProvider).value;

      var vise = _enseignantVise;
      if (_estEnseignant && user != null) {
        final sien = enseignants.firstWhere(
          (ligne) => _entier(ligne['user']) == user.id,
          orElse: () => const <String, dynamic>{},
        );
        final sienId = _entier(sien['id']);
        vise = sienId > 0 ? sienId : null;
      } else {
        vise ??= enseignants.isEmpty ? null : _entier(enseignants.first['id']);
      }

      final campagne = await _chargerLaCampagne(depot);
      final grille = await depot.fetchGrid(
        teacherId: vise,
        startHour: _heureDebut,
        endHour: _heureFin,
        slotMinutes: _pas,
      );

      if (!mounted) return;
      setState(() {
        _enseignants = enseignants;
        _enseignantVise = vise;
        _campagne = campagne;
        _grille = grille;
        // L'enseignant ne vient ici que pour déclarer; l'administration
        // ouvre sur la vue d'arbitrage, celle qui sert à placer les cours.
        if (_estEnseignant) _modeDeclaration = true;
      });
      await _chargerMonEtatDeReponse(depot, campagne, vise);
    } catch (error) {
      if (!mounted) return;
      setState(() => _erreur = _message(error, 'Chargement des disponibilités impossible.'));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<List<Map<String, dynamic>>> _chargerLesEnseignants() async {
    final reponse = await ref.read(dioProvider).get(
      '/teachers/',
      queryParameters: const {'page_size': 300},
    );
    final data = reponse.data;
    final lignes = data is Map<String, dynamic> && data['results'] is List
        ? data['results'] as List<dynamic>
        : (data is List<dynamic> ? data : const <dynamic>[]);
    return lignes
        .whereType<Map>()
        .map((ligne) => Map<String, dynamic>.from(ligne))
        .toList(growable: false);
  }

  Future<AvailabilityCampaign?> _chargerLaCampagne(
    AvailabilityRepository depot,
  ) async {
    try {
      return await depot.fetchCampagneCourante();
    } catch (_) {
      // Une école qui n'a pas encore adopté les campagnes doit continuer à
      // déclarer comme avant: l'absence de campagne n'est pas une panne.
      return null;
    }
  }

  Future<void> _chargerMonEtatDeReponse(
    AvailabilityRepository depot,
    AvailabilityCampaign? campagne,
    int? vise,
  ) async {
    if (campagne == null || vise == null || !_estEnseignant) return;
    try {
      final reponses = await depot.fetchReponses(campagne.id);
      final mienne = reponses.where((ligne) => ligne.teacherId == vise);
      if (!mounted) return;
      setState(() => _dejaRendu = mienne.isNotEmpty && mienne.first.isSubmitted);
    } catch (_) {
      // Le suivi peut être fermé au profil enseignant selon la matrice: son
      // absence ne doit pas empêcher de déclarer.
    }
  }

  // --- Déclarer ------------------------------------------------------------

  /// Fait tourner une case: préférée → possible → indisponible → rien.
  Future<void> _basculer(AvailabilityCell cellule) async {
    final vise = _enseignantVise;
    if (vise == null) {
      _signaler('Sélectionnez d’abord un enseignant.');
      return;
    }

    final actuel = cellule.mine;
    // Une plage plus large couvre cette case sans lui appartenir: la
    // modifier d'ici découperait la déclaration d'origine, ce qui demande
    // une décision que l'écran ne peut pas prendre à la place du déclarant.
    if (actuel != null && !cellule.mineExact) {
      _signaler(
        'Cette case est couverte par une plage plus large. '
        'Modifiez-la depuis la case où elle commence.',
      );
      return;
    }

    final suivant = actuel == null ? AvailabilityKind.preferred : actuel.suivant;

    setState(() => _enCours = true);
    try {
      final depot = ref.read(availabilityRepositoryProvider);
      if (suivant == null) {
        await depot.retirer(cellule.mineId!);
      } else if (cellule.mineId != null) {
        await depot.changerLEtat(cellule.mineId!, suivant);
      } else {
        await depot.declarer(
          dayOfWeek: cellule.dayOfWeek,
          startTime: cellule.startTime,
          endTime: cellule.endTime,
          kind: suivant,
          teacherId: _estEnseignant ? null : vise,
        );
      }
      await _rafraichirLaGrille();
    } catch (error) {
      _signaler(_message(error, 'Modification impossible.'));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _rafraichirLaGrille() async {
    final grille = await ref.read(availabilityRepositoryProvider).fetchGrid(
      teacherId: _enseignantVise,
      startHour: _heureDebut,
      endHour: _heureFin,
      slotMinutes: _pas,
    );
    if (!mounted) return;
    setState(() => _grille = grille);
  }

  Future<void> _rendre() async {
    final campagne = _campagne;
    if (campagne == null) return;
    setState(() => _enCours = true);
    try {
      await ref.read(availabilityRepositoryProvider).rendre(campagne.id);
      if (!mounted) return;
      setState(() => _dejaRendu = true);
      _signaler('Disponibilités transmises à l’administration.', succes: true);
    } catch (error) {
      _signaler(_message(error, 'Transmission impossible.'));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  // --- Arbitrer ------------------------------------------------------------

  Future<void> _relancer() async {
    final campagne = _campagne;
    if (campagne == null) return;
    setState(() => _enCours = true);
    try {
      final envoyees = await ref
          .read(availabilityRepositoryProvider)
          .relancer(campagne.id);
      if (!mounted) return;
      _signaler(
        envoyees == 0
            ? 'Tout le monde a déjà répondu.'
            : '$envoyees enseignant${envoyees > 1 ? 's' : ''} relancé'
                  '${envoyees > 1 ? 's' : ''}.',
        succes: true,
      );
      await _charger();
    } catch (error) {
      _signaler(_message(error, 'Relance impossible.'));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _voirLesReponses() async {
    final campagne = _campagne;
    if (campagne == null) return;
    try {
      final reponses = await ref
          .read(availabilityRepositoryProvider)
          .fetchReponses(campagne.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CampaignResponsesDialog(
          titre: campagne.label,
          reponses: reponses,
          onRelancer: campagne.isOpen && _peutEcrire
              ? () {
                  Navigator.of(context).pop();
                  _relancer();
                }
              : null,
        ),
      );
    } catch (error) {
      _signaler(_message(error, 'Suivi indisponible.'));
    }
  }

  void _detailDeLaCase(AvailabilityCell cellule) {
    showDialog<void>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: Text('${cellule.dayLabel} ${cellule.creneau}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final declarant in cellule.teachers)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    switch (declarant.kind) {
                      AvailabilityKind.preferred => Icons.star_rounded,
                      AvailabilityKind.possible => Icons.check_rounded,
                      _ => Icons.block_rounded,
                    },
                    size: 18,
                  ),
                  title: Text(declarant.name),
                  subtitle: Text(declarant.kind?.libelle ?? ''),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  // --- Rouages -------------------------------------------------------------

  int _entier(dynamic valeur) {
    if (valeur is int) return valeur;
    return int.tryParse(valeur?.toString() ?? '') ?? 0;
  }

  String _libelleEnseignant(Map<String, dynamic> ligne) {
    final nom = (ligne['user_full_name'] ?? '').toString().trim();
    final code = (ligne['employee_code'] ?? '').toString().trim();
    if (nom.isEmpty) return code.isEmpty ? 'Enseignant' : code;
    return code.isEmpty ? nom : '$code • $nom';
  }

  String _message(Object error, String repli) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        for (final valeur in data.values) {
          if (valeur is List && valeur.isNotEmpty) return valeur.first.toString();
          if (valeur is String && valeur.isNotEmpty) return valeur;
        }
      }
    }
    return repli;
  }

  void _signaler(String message, {bool succes = false}) {
    if (!mounted) return;
    const vert = Color(0xFF197A43);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: succes ? vert : null,
          content: Text(
            message,
            style: succes ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final estEnseignant = _estEnseignant;
    final peutEcrire = _peutEcrire;

    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Disponibilités des enseignants',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            estEnseignant
                ? 'Déclarez les créneaux que vous pouvez assurer. '
                      'Ils servent à construire l’emploi du temps.'
                : 'Ce que les enseignants déclarent avant la construction de '
                      'l’emploi du temps. Plusieurs peuvent être disponibles sur '
                      'le même créneau : c’est la marge dont vous disposez.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          CampaignBanner(
            campagne: _campagne,
            vueEnseignant: estEnseignant,
            dejaRendu: _dejaRendu,
            onRendre: _enCours ? null : _rendre,
            onRelancer: _enCours || !peutEcrire ? null : _relancer,
            onVoirLesReponses: _voirLesReponses,
          ),
          const SizedBox(height: 14),
          if (_erreur != null) ...[
            Text(
              _erreur!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (_enCours) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 10),
          ],
          _barreDOutils(context, estEnseignant),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AvailabilityGridView(
                grid: _grille,
                modeDeclaration: _modeDeclaration,
                onBasculer: (_modeDeclaration && peutEcrire && !_enCours)
                    ? _basculer
                    : null,
                onDetail: _modeDeclaration ? null : _detailDeLaCase,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barreDOutils(BuildContext context, bool estEnseignant) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!estEnseignant)
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.groups_outlined, size: 18),
                label: Text('Vue d’ensemble'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.edit_calendar_outlined, size: 18),
                label: Text('Saisir pour un enseignant'),
              ),
            ],
            selected: {_modeDeclaration},
            onSelectionChanged: (choix) =>
                setState(() => _modeDeclaration = choix.first),
          ),
        if (!estEnseignant)
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<int>(
              initialValue: _enseignantVise,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Enseignant',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final ligne in _enseignants)
                  DropdownMenuItem(
                    value: _entier(ligne['id']),
                    child: Text(
                      _libelleEnseignant(ligne),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _enCours
                  ? null
                  : (valeur) {
                      setState(() => _enseignantVise = valeur);
                      _rafraichirLaGrille();
                    },
            ),
          ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _pas,
            decoration: const InputDecoration(
              labelText: 'Pas horaire',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 minutes')),
              DropdownMenuItem(value: 60, child: Text('1 heure')),
              DropdownMenuItem(value: 120, child: Text('2 heures')),
            ],
            onChanged: _enCours
                ? null
                : (valeur) {
                    if (valeur == null) return;
                    setState(() => _pas = valeur);
                    _rafraichirLaGrille();
                  },
          ),
        ),
        OutlinedButton.icon(
          onPressed: _enCours ? null : _charger,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualiser'),
        ),
      ],
    );
  }
}
