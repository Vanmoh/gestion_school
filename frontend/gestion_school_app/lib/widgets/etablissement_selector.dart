import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/etablissement.dart';

import '../screens/etablissement_details_screen.dart';

class EtablissementSelector extends ConsumerWidget {
  final void Function(Etablissement) onSelected;

  const EtablissementSelector({Key? key, required this.onSelected}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissements = ref.watch(etablissementProvider).etablissements;

    if (etablissements.isEmpty) {
      return const Center(child: Text('Aucun établissement disponible.'));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.6,
        ),
        itemCount: etablissements.length,
        itemBuilder: (context, index) {
          final etab = etablissements[index];
          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: etab.logoUrl != null && etab.logoUrl!.isNotEmpty
                        ? Image.network(etab.logoUrl!, fit: BoxFit.cover, width: double.infinity)
                        : Image.asset('assets/etablissement_placeholder.jpg', fit: BoxFit.cover, width: double.infinity),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(etab.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      if (etab.address != null && etab.address!.isNotEmpty)
                        Text(etab.address!, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.person),
                        label: const Text('Accéder'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(90, 36),
                        ),
                        onPressed: () {
                          ref.read(etablissementProvider).selectEtablissement(etab);
                          onSelected(etab);
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Voir Détails'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(90, 36),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EtablissementDetailsScreen(etablissement: etab),
                            ),
                          );
                        },
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
  }
}
