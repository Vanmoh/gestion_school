import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/etablissement.dart';

import '../screens/etablissement_details_screen.dart';

class EtablissementSelector extends ConsumerWidget {
  final FutureOr<void> Function(Etablissement) onSelected;

  const EtablissementSelector({super.key, required this.onSelected});

  String _subtitle(Etablissement etab) {
    if (etab.address != null && etab.address!.trim().isNotEmpty) {
      return etab.address!.trim();
    }
    if (etab.email != null && etab.email!.trim().isNotEmpty) {
      return etab.email!.trim();
    }
    return 'Établissement scolaire';
  }

  List<Etablissement> _fallbackEtablissements() {
    return [
      Etablissement(id: -101, name: 'CTOB', address: 'Collège Technique OBK'),
      Etablissement(id: -102, name: 'LOBK', address: 'Lycée OBK'),
      Etablissement(
        id: -103,
        name: 'IFP-OBK',
        address: 'Institut de Formation Professionnelle',
      ),
      Etablissement(
        id: -104,
        name: 'Complexe Scolaire',
        address: 'École Maternelle & Primaire',
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissements = ref.watch(etablissementProvider).etablissements;
    final displayEtablissements =
        (etablissements.isNotEmpty ? etablissements : _fallbackEtablissements())
            .take(4)
            .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final tightLayout = height < 720;
        final crossAxisCount = width >= 520 ? 2 : 1;
        final spacing = tightLayout ? 6.0 : 10.0;
        final rows = (displayEtablissements.length / crossAxisCount).ceil();
        final usableWidth = width - spacing * (crossAxisCount - 1);
        final usableHeight = height - spacing * (rows - 1);
        final tileWidth = usableWidth / crossAxisCount;
        final tileHeight = usableHeight / rows;
        // Keep a safe range so cards stay readable on both short and tall screens.
        final computedAspectRatio = ((tileWidth / tileHeight) * 1.18).clamp(
          1.35,
          2.80,
        );

        return Padding(
          padding: EdgeInsets.zero,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: computedAspectRatio,
            ),
            itemCount: displayEtablissements.length,
            itemBuilder: (context, index) {
              final etab = displayEtablissements[index];
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFD6E3F1)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1C27517F),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        tightLayout ? 8 : 10,
                        tightLayout ? 4 : 7,
                        tightLayout ? 8 : 10,
                        tightLayout ? 3 : 5,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              etab.name,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: tightLayout ? 13 : 16,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF1E4674),
                              ),
                            ),
                          ),
                          SizedBox(height: tightLayout ? 1 : 2),
                          SizedBox(
                            width: double.infinity,
                            child: Text(
                              _subtitle(etab),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: tightLayout ? 10 : 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF576C87),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: tightLayout ? 7 : 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFF9FCFF), Color(0xFFEDF4FD)],
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child:
                              etab.logoUrlForDisplay != null &&
                                  etab.logoUrlForDisplay!.isNotEmpty
                              ? Image.network(
                                  etab.logoUrlForDisplay!,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Image.asset(
                                        'assets/images/ecole_photo.png',
                                        fit: BoxFit.contain,
                                        width: double.infinity,
                                      ),
                                )
                              : Image.asset(
                                  'assets/images/ecole_photo.png',
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        tightLayout ? 7 : 9,
                        tightLayout ? 4 : 6,
                        tightLayout ? 7 : 9,
                        tightLayout ? 5 : 7,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: Icon(
                                Icons.person,
                                size: tightLayout ? 13 : 14,
                              ),
                              label: const Text('Accéder'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2A5F99),
                                foregroundColor: Colors.white,
                                minimumSize: Size(0, tightLayout ? 28 : 32),
                                textStyle: TextStyle(
                                  fontSize: tightLayout ? 11 : 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () async {
                                try {
                                  await onSelected(etab);
                                } catch (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Impossible d\'ouvrir l\'établissement: $error',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          SizedBox(width: tightLayout ? 6 : 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(
                                Icons.info_outline,
                                size: tightLayout ? 13 : 14,
                              ),
                              label: const Text('Voir Détails'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2A5F99),
                                minimumSize: Size(0, tightLayout ? 28 : 32),
                                textStyle: TextStyle(
                                  fontSize: tightLayout ? 11 : 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                side: const BorderSide(
                                  color: Color(0xFF7EA6CF),
                                ),
                                backgroundColor: const Color(0xFFF7FAFE),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EtablissementDetailsScreen(
                                      etablissement: etab,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
