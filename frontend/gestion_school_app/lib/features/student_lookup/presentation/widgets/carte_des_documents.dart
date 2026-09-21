import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/roster_pdf_preview_dialog.dart';
import '../../../students/domain/student.dart';

/// Ce qu'on saura de la classe avant d'engager le papier.
class VerificationDesCartes {
  final int effectif;
  final int sansPhoto;
  final List<String> nomsSansPhoto;
  final bool qrActif;
  final String motifQr;
  final int cartesParPlanche;

  const VerificationDesCartes({
    required this.effectif,
    required this.sansPhoto,
    required this.nomsSansPhoto,
    required this.qrActif,
    required this.motifQr,
    required this.cartesParPlanche,
  });

  factory VerificationDesCartes.fromJson(Map<String, dynamic> json) {
    return VerificationDesCartes(
      effectif: (json['effectif'] as num?)?.toInt() ?? 0,
      sansPhoto: (json['sans_photo'] as num?)?.toInt() ?? 0,
      nomsSansPhoto:
          (json['noms_sans_photo'] as List?)
              ?.map((valeur) => valeur.toString())
              .toList() ??
          const [],
      qrActif: json['qr_actif'] == true,
      motifQr: (json['motif_qr'] ?? '').toString(),
      cartesParPlanche: (json['cartes_par_planche'] as num?)?.toInt() ?? 0,
    );
  }

  bool get riensASignaler => sansPhoto == 0 && qrActif;

  int get planches => cartesParPlanche <= 0
      ? 0
      : (effectif + cartesParPlanche - 1) ~/ cartesParPlanche;
}

/// Les pièces qu'une famille vient chercher, réunies dans le dossier.
///
/// Elles vivaient ailleurs: la carte scolaire et le certificat derrière un
/// bouton de « Gestion des élèves », les cartes d'une classe dans un menu
/// « … » de la même page, et un troisième jeu de réglages sur la page
/// Rapports. Or c'est ici qu'on ouvre le dossier d'un élève pour en tirer un
/// papier.
class CarteDesDocuments extends ConsumerStatefulWidget {
  final Student student;

  const CarteDesDocuments({super.key, required this.student});

  @override
  ConsumerState<CarteDesDocuments> createState() => _CarteDesDocumentsState();
}

class _CarteDesDocumentsState extends ConsumerState<CarteDesDocuments> {
  /// Le format d'une carte bancaire: celui des porte-badges et des poches.
  /// L'A6 fait 148 × 105 mm, une demi-carte postale qu'aucun élève ne garde.
  ///
  /// Le serveur, lui, garde « a6 » par défaut pour ne pas changer le sens des
  /// liens déjà enregistrés: l'interface envoie donc toujours son choix.
  String _format = 'cr80';

  /// Planche à découper, ou une carte par page pour une imprimante à cartes.
  String _disposition = 'a4';

  Future<VerificationDesCartes>? _verification;

  @override
  void initState() {
    super.initState();
    _relancerLaVerification();
  }

  @override
  void didUpdateWidget(covariant CarteDesDocuments ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.student.classroomId != widget.student.classroomId) {
      _relancerLaVerification();
    }
  }

  void _relancerLaVerification() {
    final classe = widget.student.classroomId;
    setState(() {
      _verification = classe == null ? null : _verifier(classe);
    });
  }

  Future<VerificationDesCartes> _verifier(int classe) async {
    final reponse = await ref
        .read(dioProvider)
        .get<Map<String, dynamic>>(
          '/reports/student-cards/class/$classe/verification/',
          queryParameters: {'card_format': _format},
        );
    return VerificationDesCartes.fromJson(reponse.data ?? const {});
  }

  Future<Uint8List> _telecharger(
    String chemin,
    Map<String, dynamic> parametres,
  ) async {
    final reponse = await ref
        .read(dioProvider)
        .get<List<int>>(
          chemin,
          queryParameters: {
            ...parametres,
            // L'horodatage évite qu'un navigateur serve la pièce de l'élève
            // précédent depuis son cache.
            '_ts': DateTime.now().millisecondsSinceEpoch,
          },
          options: Options(responseType: ResponseType.bytes),
        );
    final octets = reponse.data;
    if (octets == null || octets.isEmpty) {
      throw Exception('Document vide');
    }
    return Uint8List.fromList(octets);
  }

  Future<void> _ouvrir({
    required String titre,
    required String nomFichier,
    required String chemin,
    Map<String, dynamic> parametres = const {},
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => RosterPdfPreviewDialog(
        titre: titre,
        nomFichier: nomFichier,
        charger: () => _telecharger(chemin, parametres),
      ),
    );
  }

  /// Imprimer une classe engage une planche qu'on découpe: ce qui manque se
  /// dit avant, pas sur le carton déjà coupé.
  Future<void> _ouvrirLesCartesDeLaClasse(int classe) async {
    VerificationDesCartes? etat;
    try {
      etat = await _verifier(classe);
    } catch (_) {
      // Le contrôle préalable n'est pas l'impression: s'il échoue, on laisse
      // l'aperçu se charger et dire lui-même ce qui ne va pas.
      etat = null;
    }
    if (!mounted) return;

    if (etat != null && !etat.riensASignaler) {
      final continuer = await _confirmer(etat);
      if (continuer != true || !mounted) return;
    }

    await _ouvrir(
      titre: 'Cartes — ${widget.student.classroomName}',
      nomFichier: 'cartes_classe_$classe.pdf',
      chemin: '/reports/student-cards/class/$classe/',
      parametres: {'layout_mode': _disposition, 'card_format': _format},
    );
  }

  Future<bool?> _confirmer(VerificationDesCartes etat) {
    return showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Avant d\'imprimer'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (etat.sansPhoto > 0) ...[
                Text(
                  '${etat.sansPhoto} élève(s) sur ${etat.effectif} n\'ont pas '
                  'de photo: leur carte sortira avec un cadre vide.',
                ),
                if (etat.nomsSansPhoto.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    etat.nomsSansPhoto.join(', ') +
                        (etat.sansPhoto > etat.nomsSansPhoto.length
                            ? ', …'
                            : ''),
                    style: Theme.of(contexte).textTheme.bodySmall,
                  ),
                ],
              ],
              if (etat.sansPhoto > 0 && !etat.qrActif)
                const SizedBox(height: 14),
              if (!etat.qrActif) Text(etat.motifQr),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexte).pop(true),
            child: const Text('Imprimer quand même'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final eleve = widget.student;
    final classe = eleve.classroomId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Documents', style: textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pièces délivrées à la demande d\'une famille.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                key: const Key('dossier-format-carte'),
                isExpanded: true,
                initialValue: _format,
                decoration: const InputDecoration(
                  labelText: 'Format de carte',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'cr80',
                    child: Text('Carte bancaire — 85,6 × 54 mm'),
                  ),
                  DropdownMenuItem(
                    value: 'a6',
                    child: Text('A6 — 148 × 105 mm'),
                  ),
                ],
                onChanged: (valeur) {
                  setState(() => _format = valeur ?? 'cr80');
                  _relancerLaVerification();
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  key: const Key('dossier-carte-scolaire'),
                  onPressed: () => _ouvrir(
                    titre: 'Carte scolaire — ${eleve.fullName}',
                    nomFichier: 'carte_${eleve.matricule}.pdf',
                    chemin: '/reports/student-card/${eleve.id}/',
                    parametres: {'card_format': _format},
                  ),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Carte scolaire'),
                ),
                OutlinedButton.icon(
                  key: const Key('dossier-certificat'),
                  onPressed: () => _ouvrir(
                    titre: 'Certificat de fréquentation — ${eleve.fullName}',
                    nomFichier: 'certificat_${eleve.matricule}.pdf',
                    chemin: '/reports/certificat-frequentation/${eleve.id}/',
                  ),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Certificat de fréquentation'),
                ),
              ],
            ),
            const Divider(height: 26),
            Text('Cartes de toute la classe', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              // Le motif de ce bouton: on imprime les cartes d'une classe
              // entière à la rentrée, jamais une par une.
              classe == null
                  ? 'Cet élève n\'est affecté à aucune classe.'
                  : 'Toute la classe de ${eleve.classroomName}, en une fois.',
              style: textTheme.bodySmall,
            ),
            if (classe != null) _resume(textTheme, scheme),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: const Key('dossier-disposition-cartes'),
                    isExpanded: true,
                    initialValue: _disposition,
                    decoration: const InputDecoration(
                      labelText: 'Mise en page',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'a4',
                        child: Text('Planche A4 à découper'),
                      ),
                      DropdownMenuItem(
                        value: 'standard',
                        child: Text('1 carte par page'),
                      ),
                    ],
                    onChanged: classe == null
                        ? null
                        : (valeur) =>
                              setState(() => _disposition = valeur ?? 'a4'),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('dossier-cartes-classe'),
                  onPressed: classe == null
                      ? null
                      : () => _ouvrirLesCartesDeLaClasse(classe),
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: const Text('Cartes de la classe'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Ce que donnera l'impression, avant de la lancer.
  Widget _resume(TextTheme textTheme, ColorScheme scheme) {
    final verification = _verification;
    if (verification == null) return const SizedBox.shrink();

    return FutureBuilder<VerificationDesCartes>(
      future: verification,
      builder: (context, instantane) {
        final etat = instantane.data;
        if (etat == null) return const SizedBox.shrink();

        final lignes = <String>[
          if (_disposition == 'a4' && etat.planches > 0)
            '${etat.effectif} cartes, ${etat.planches} planche(s) A4 '
                '(${etat.cartesParPlanche} par feuille, taille réelle)',
          if (etat.sansPhoto > 0)
            '${etat.sansPhoto} élève(s) sans photo',
          if (!etat.qrActif) 'Sans QR de vérification',
        ];
        if (lignes.isEmpty) return const SizedBox.shrink();

        final alerte = etat.sansPhoto > 0 || !etat.qrActif;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                alerte ? Icons.warning_amber_outlined : Icons.info_outline,
                size: 15,
                color: alerte ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lignes.join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: alerte ? scheme.error : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
