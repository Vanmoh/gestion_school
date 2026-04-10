import 'package:flutter/material.dart';
import '../models/etablissement.dart';

class EtablissementDetailsScreen extends StatelessWidget {
  final Etablissement etablissement;
  const EtablissementDetailsScreen({super.key, required this.etablissement});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Détails de l\'établissement')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              etablissement.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (etablissement.address != null &&
                etablissement.address!.isNotEmpty)
              Text(
                etablissement.address!,
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            if (etablissement.logoUrlForDisplay != null &&
                etablissement.logoUrlForDisplay!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    etablissement.logoUrlForDisplay!,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            // Ajoutez ici d'autres champs si besoin
          ],
        ),
      ),
    );
  }
}
