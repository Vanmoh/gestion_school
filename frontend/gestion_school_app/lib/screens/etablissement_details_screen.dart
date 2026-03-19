import 'package:flutter/material.dart';
import '../models/etablissement.dart';

class EtablissementDetailsScreen extends StatelessWidget {
  final Etablissement etablissement;
  const EtablissementDetailsScreen({Key? key, required this.etablissement}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Détails de l\'établissement'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etablissement.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (etablissement.description != null)
              Text(etablissement.description!, style: const TextStyle(fontSize: 16)),
            if (etablissement.address != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Text(etablissement.address!, style: const TextStyle(fontSize: 15, color: Colors.black54)),
                  ],
                ),
              ),
            if (etablissement.imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(etablissement.imageUrl!, height: 180, fit: BoxFit.cover),
                ),
              ),
            // Ajoutez ici d'autres champs si besoin
          ],
        ),
      ),
    );
  }
}
