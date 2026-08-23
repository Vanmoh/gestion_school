import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// Absences et retards en lecture, pour les parents et les eleves.
///
/// Jusqu'ici, les familles ouvraient la page d'administration: un formulaire
/// de saisie inerte, des selecteurs de classe sans objet. Le meme constat
/// avait deja conduit a une page dediee pour la discipline; les absences
/// etaient restees sans equivalent.
///
/// `AttendanceViewSet.get_queryset` restreint deja la reponse a l'eleve
/// connecte ou aux enfants du parent: cette page ne refait aucun filtrage,
/// elle presente ce qu'elle recoit.
class ParentAttendancePage extends ConsumerStatefulWidget {
  const ParentAttendancePage({super.key});

  @override
  ConsumerState<ParentAttendancePage> createState() =>
      _ParentAttendancePageState();
}

class _ParentAttendancePageState extends ConsumerState<ParentAttendancePage> {
  bool _loading = true;
  bool _restricted = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _lignes = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await ref.read(dioProvider).get('/attendances/');
      if (!mounted) return;
      setState(() {
        _lignes = _extraireLignes(response.data);
        _restricted = false;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final statut = error.response?.statusCode;
      setState(() {
        _restricted = statut == 403;
        _errorMessage = _restricted
            ? null
            : 'Impossible de charger les absences (${statut ?? 'réseau'}).';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Impossible de charger les absences: $error';
        _loading = false;
      });
    }
  }

  static List<Map<String, dynamic>> _extraireLignes(dynamic data) {
    final brut = data is Map<String, dynamic> && data['results'] is List
        ? data['results'] as List
        : (data is List ? data : const []);
    return brut
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  /// Regroupe par enfant: un parent de trois eleves recevait une liste unique
  /// ou il fallait deviner de qui parlait chaque ligne.
  Map<String, List<Map<String, dynamic>>> get _parEnfant {
    final groupes = <String, List<Map<String, dynamic>>>{};
    for (final ligne in _lignes) {
      final nom = (ligne['student_full_name'] ?? '').toString().trim();
      groupes.putIfAbsent(nom.isEmpty ? 'Élève' : nom, () => []).add(ligne);
    }
    return groupes;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_restricted) {
      return _Message(
        icone: Icons.lock_outline,
        texte: 'Votre profil n’a pas accès aux absences.',
      );
    }
    if (_errorMessage != null) {
      return _Message(
        icone: Icons.error_outline,
        texte: _errorMessage!,
        onRetry: _load,
      );
    }
    if (_lignes.isEmpty) {
      return _Message(
        icone: Icons.check_circle_outline,
        texte: 'Aucune absence ni retard enregistré.',
        onRetry: _load,
      );
    }

    final groupes = _parEnfant;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entree in groupes.entries) ...[
            _EnTeteEnfant(
              nom: entree.key,
              lignes: entree.value,
              scheme: scheme,
              textTheme: textTheme,
            ),
            const SizedBox(height: 8),
            for (final ligne in entree.value)
              _Ligne(ligne: ligne, scheme: scheme, textTheme: textTheme),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _EnTeteEnfant extends StatelessWidget {
  final String nom;
  final List<Map<String, dynamic>> lignes;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _EnTeteEnfant({
    required this.nom,
    required this.lignes,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final absences = lignes.where((l) => l['is_absent'] == true).length;
    final retards = lignes.where((l) => l['is_late'] == true).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nom,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (absences > 0) '$absences absence${absences > 1 ? 's' : ''}',
            if (retards > 0) '$retards retard${retards > 1 ? 's' : ''}',
          ].join('  ·  '),
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  final Map<String, dynamic> ligne;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _Ligne({
    required this.ligne,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final absent = ligne['is_absent'] == true;
    final retard = ligne['is_late'] == true;
    final motif = (ligne['reason'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(
          absent ? Icons.event_busy_outlined : Icons.schedule_outlined,
          color: absent ? scheme.error : scheme.tertiary,
        ),
        title: Text(_date(ligne['date'])),
        subtitle: Text(
          [
            if (absent) 'Absent',
            if (retard) 'En retard',
            // Un motif vide ne se dit pas: la ligne serait plus longue sans
            // rien apprendre.
            if (motif.isNotEmpty) motif,
          ].join('  ·  '),
        ),
      ),
    );
  }

  static String _date(dynamic valeur) {
    final brut = (valeur ?? '').toString();
    final date = DateTime.tryParse(brut);
    if (date == null) return brut;
    final jour = date.day.toString().padLeft(2, '0');
    final mois = date.month.toString().padLeft(2, '0');
    return '$jour/$mois/${date.year}';
  }
}

class _Message extends StatelessWidget {
  final IconData icone;
  final String texte;
  final VoidCallback? onRetry;

  const _Message({required this.icone, required this.texte, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              texte,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
