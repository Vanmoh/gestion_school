import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 4 — le censeur, qui arbitre la pédagogie.
///
/// Son chapitre ouvre la double validation de la paie : il vise au niveau un,
/// le comptable visera au niveau deux au chapitre suivant. C'est la règle la
/// plus difficile à expliquer sans voix, et la plus convaincante à montrer — à
/// condition que les deux chapitres se suivent.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre du censeur', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'censor',
      identifiant: 'censeur',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        pilote.journal.dire(
          'Le censeur a son propre tableau de bord.',
          duree: const Duration(seconds: 4),
        );
        await pilote.poser(duree: const Duration(seconds: 3));

        if (await pilote.ouvrirLeModule(
          'attendance',
          sousTitre: 'Deux émargements sous une entrée : élèves, et enseignants.',
        )) {
          await pilote.ouvrirLOnglet('Enseignants');
          await pilote.soulignerLaCle(
            'pointage-enregistrer',
            texte: 'Le pointage des enseignants alimente la paie.',
          );
        }

        if (await pilote.ouvrirLeModule(
          'discipline',
          sousTitre: 'L\'enseignant déclare ; le censeur arbitre.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule(
          'finance',
          sousTitre: 'La paie se vise à deux : ici, le premier visa.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'academic_imports',
          sousTitre: 'Importer une classe entière depuis un tableur.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
