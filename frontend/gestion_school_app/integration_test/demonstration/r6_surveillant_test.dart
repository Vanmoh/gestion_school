import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 6 — le surveillant, qui tient la discipline et les épreuves.
///
/// Deux gestes n'appartiennent qu'à lui : verrouiller une feuille d'appel, et
/// saisir la conduite — une note qui compte dans la moyenne, avec son
/// coefficient, comme n'importe quelle matière.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre du surveillant', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'supervisor',
      identifiant: 'surveillant1',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        await pilote.poser(duree: const Duration(seconds: 3));

        if (await pilote.ouvrirLeModule(
          'attendance',
          sousTitre: 'L\'appel se fait, puis se verrouille.',
        )) {
          await pilote.soulignerLaCle(
            'emargement-valider-verrouiller',
            texte: 'Verrouiller arrête la feuille : plus personne ne la retouche.',
          );
          await pilote.soulignerLaCle(
            'emargement-enregistrer-conduite',
            texte: 'La conduite est une note, avec son coefficient.',
          );
        }

        if (await pilote.ouvrirLeModule(
          'discipline',
          sousTitre: 'Déclarer un incident : l\'élève, le motif, la gravité.',
        )) {
          await pilote.appuyerSurLaCle('basculer-declaration');
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'exams',
          sousTitre: 'Ce qu\'il faut voir avant les compositions : les épreuves sans surveillant.',
        )) {
          await pilote.ouvrirLOnglet('Surveillance');
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule('library')) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
