import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 7 — l'enseignant, et la frontière entre corriger et publier.
///
/// C'est le chapitre où la saisie se voit : les notes sont frappées **chiffre
/// par chiffre**, parce qu'un champ qui se remplit d'un coup ne ressemble à
/// rien à l'image.
///
/// Et c'est le chapitre d'une absence : il corrige, il saisit, mais il ne
/// publie pas. L'affinement `publication_des_examens` réserve ce geste à la
/// direction et au censeur. Montrer un bouton qui n'est pas là demande de le
/// dire, d'où le sous-titre.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre de l_enseignant', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'teacher',
      identifiant: 'enseignant1',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        pilote.journal.dire(
          'Ses classes, ses heures, ses copies à rendre.',
          duree: const Duration(seconds: 4),
        );
        await pilote.poser(duree: const Duration(seconds: 3));

        if (await pilote.ouvrirLeModule(
          'grades',
          sousTitre: 'La note de classe, puis la composition.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'attendance',
          sousTitre: 'Il pointe ses propres heures.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule(
          'timetable',
          sousTitre: 'Avant la grille : ses disponibilités, qu\'il déclare lui-même.',
        )) {
          await pilote.ouvrirLOnglet('Disponibilités');
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'exams',
          sousTitre: 'Corriger n\'est pas publier : le bouton ne lui est pas offert.',
        )) {
          await pilote.ouvrirLOnglet('Calendrier');
          await pilote.poser(duree: const Duration(seconds: 5));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
