import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/motif_du_refus.dart';
import '../../../core/network/api_client.dart';
import 'student_lookup_page.dart';

/// Le dossier d'un élève, ou ceux des enfants d'un parent, sans chercher.
///
/// Les familles ouvraient l'écran « Dossier élève » et tombaient sur une barre
/// de recherche. Un élève n'a pourtant qu'un dossier à consulter — le sien — et
/// un parent ceux de ses enfants. Leur demander de taper un nom, c'est leur
/// demander de retrouver ce qu'ils savent déjà ; et la barre laissait croire
/// qu'ils pouvaient ouvrir le dossier de n'importe qui, alors que le serveur
/// le leur refuse.
///
/// `StudentViewSet.get_queryset` restreint déjà `/students/` à l'élève connecté
/// ou aux enfants du parent : cette page ne refait aucun filtrage, elle présente
/// ce qu'elle reçoit. Même principe que les pages famille des absences, de la
/// discipline et des examens.
///
/// **Un seul dossier s'ouvre directement, plusieurs se choisissent.** Un parent
/// d'un seul enfant n'a rien à choisir, et lui présenter une liste d'une ligne
/// serait un clic pour rien.
class DossierDeLaFamillePage extends ConsumerStatefulWidget {
  const DossierDeLaFamillePage({super.key});

  @override
  ConsumerState<DossierDeLaFamillePage> createState() =>
      _DossierDeLaFamillePageState();
}

class _DossierDeLaFamillePageState
    extends ConsumerState<DossierDeLaFamillePage> {
  bool _chargement = true;
  String _erreur = '';
  List<Map<String, dynamic>> _enfants = const [];
  int? _choisi;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_charger);
  }

  Future<void> _charger() async {
    if (mounted) setState(() => _chargement = true);
    try {
      final reponse = await ref.read(dioProvider).get('/students/');
      final donnees = reponse.data;
      final lignes = donnees is Map<String, dynamic> && donnees['results'] is List
          ? donnees['results'] as List<dynamic>
          : (donnees is List<dynamic> ? donnees : const <dynamic>[]);
      final enfants = lignes
          .whereType<Map>()
          .map((ligne) => Map<String, dynamic>.from(ligne))
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _enfants = enfants;
        // Un seul dossier: on l'ouvre. C'est le cas de tout élève, et du
        // parent d'un enfant unique.
        _choisi = enfants.length == 1 ? _entier(enfants.first['id']) : null;
        _erreur = '';
      });
    } on DioException catch (erreur) {
      if (!mounted) return;
      setState(() {
        _erreur = motifDuRefus(
          erreur,
          parDefaut: 'Impossible de charger le dossier.',
        );
      });
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erreur.isNotEmpty) {
      return _Message(
        icone: Icons.error_outline,
        titre: 'Dossier indisponible',
        detail: _erreur,
        action: FilledButton.icon(
          onPressed: _charger,
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer'),
        ),
      );
    }

    if (_enfants.isEmpty) {
      return const _Message(
        icone: Icons.folder_off_outlined,
        titre: 'Aucun dossier',
        detail:
            'Aucun élève n’est rattaché à ce compte. Signalez-le au secrétariat '
            'de l’établissement.',
      );
    }

    final choisi = _choisi;
    if (choisi != null) {
      return Column(
        children: [
          // Le retour n'apparaît que s'il y a une liste où revenir.
          if (_enfants.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: TextButton.icon(
                  key: const Key('dossier-famille-retour'),
                  onPressed: () => setState(() => _choisi = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Mes enfants'),
                ),
              ),
            ),
          Expanded(
            child: StudentLookupPage(
              key: ValueKey('dossier-$choisi'),
              initialStudentId: choisi,
              avecRecherche: false,
            ),
          ),
        ],
      );
    }

    return _ListeDesEnfants(
      enfants: _enfants,
      onChoisir: (id) => setState(() => _choisi = id),
    );
  }

  static int _entier(dynamic valeur) {
    if (valeur is int) return valeur;
    if (valeur is num) return valeur.toInt();
    return int.tryParse('${valeur ?? ''}') ?? 0;
  }
}

class _ListeDesEnfants extends StatelessWidget {
  final List<Map<String, dynamic>> enfants;
  final void Function(int) onChoisir;

  const _ListeDesEnfants({required this.enfants, required this.onChoisir});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Mes enfants', style: textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Choisissez un enfant pour ouvrir son dossier : notes, absences, '
                'discipline et frais.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              for (final enfant in enfants)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    key: ValueKey('enfant-${enfant['id']}'),
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        _initiale(enfant),
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                    title: Text(_nom(enfant)),
                    subtitle: Text(_sousTitre(enfant)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final id =
                          _DossierDeLaFamillePageState._entier(enfant['id']);
                      if (id > 0) onChoisir(id);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _nom(Map<String, dynamic> enfant) {
    for (final cle in ['full_name', 'nom_complet', 'user_full_name']) {
      final valeur = enfant[cle]?.toString().trim() ?? '';
      if (valeur.isNotEmpty) return valeur;
    }
    final prenom = enfant['first_name']?.toString().trim() ?? '';
    final nom = enfant['last_name']?.toString().trim() ?? '';
    final complet = '$prenom $nom'.trim();
    if (complet.isNotEmpty) return complet;
    // Le matricule identifie toujours, même quand le nom manque: mieux vaut
    // un dossier nommé par son matricule qu'une ligne « Élève ».
    return enfant['matricule']?.toString() ?? 'Élève';
  }

  static String _sousTitre(Map<String, dynamic> enfant) {
    final matricule = enfant['matricule']?.toString().trim() ?? '';
    final classe = enfant['classroom_name']?.toString().trim() ?? '';
    return [
      if (classe.isNotEmpty) classe,
      if (matricule.isNotEmpty) matricule,
    ].join(' · ');
  }

  static String _initiale(Map<String, dynamic> enfant) {
    final nom = _nom(enfant).trim();
    return nom.isEmpty ? '?' : nom.characters.first.toUpperCase();
  }
}

class _Message extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String detail;
  final Widget? action;

  const _Message({
    required this.icone,
    required this.titre,
    required this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(titre, style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
