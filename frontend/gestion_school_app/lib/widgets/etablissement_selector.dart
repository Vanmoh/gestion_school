import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/etablissement.dart';

import '../screens/etablissement_details_screen.dart';

class EtablissementSelector extends ConsumerWidget {
  final void Function(Etablissement) onSelected;

  const EtablissementSelector({Key? key, required this.onSelected}) : super(key: key);

  String _subtitle(Etablissement etab) {
    if (etab.address != null && etab.address!.trim().isNotEmpty) {
      return etab.address!.trim();
    }
    if (etab.email != null && etab.email!.trim().isNotEmpty) {
      return etab.email!.trim();
    }
    return 'Établissement scolaire';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissements = ref.watch(etablissementProvider).etablissements;

    if (etablissements.isEmpty) {
      return const Center(child: Text('Aucun établissement disponible.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 720
            ? 2
            : width >= 480
            ? 2
            : 1;

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              childAspectRatio: width < 520 ? 1.08 : 1.34,
            ),
            itemCount: etablissements.length,
            itemBuilder: (context, index) {
              final etab = etablissements[index];
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A244A74),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            etab.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF264A7A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _subtitle(etab),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF4B5B72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(0),
                        child: etab.logoUrl != null && etab.logoUrl!.isNotEmpty
                            ? Image.network(
                                etab.logoUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/images/ecole_photo.png',
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                ),
                              )
                            : Image.asset(
                                'assets/images/ecole_photo.png',
                                fit: BoxFit.cover,
                                width: double.infinity,
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.person, size: 16),
                              label: const Text('Accéder'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2F5F95),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 38),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () {
                                ref.read(etablissementProvider).selectEtablissement(etab);
                                onSelected(etab);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.add_circle, size: 16),
                              label: const Text('Voir Détails'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2F5F95),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 38),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EtablissementDetailsScreen(etablissement: etab),
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
