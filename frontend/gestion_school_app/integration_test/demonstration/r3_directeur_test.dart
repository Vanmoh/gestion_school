import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 3 — le directeur, et le cœur de la démonstration.
///
/// C'est la prise qui montre le plus de métier : ouvrir l'année, **générer
/// l'emploi du temps sous les yeux du spectateur**, publier une campagne
/// d'examens, arrêter une période de notes.
///
/// La génération est le moment qui vaut la vidéo. Elle ne fonctionnait pas en
/// démonstration : `Subject.weekly_slots` valait zéro et la préparation
/// répondait « Aucune matière à placer » sur une école par ailleurs complète.
/// Depuis que `completer_le_decor_de_demonstration` pose les volumes horaires,
/// la simulation place cent trente-trois séances sur cent trente-trois — et ce
/// n'est pas une maquette, c'est le vrai calcul du serveur.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre du directeur', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'director',
      identifiant: 'directeur',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        // --- Le tableau de bord: ce que la direction voit en arrivant.
        pilote.journal.dire(
          'Le directeur arrive sur l\'état de son école.',
          duree: const Duration(seconds: 5),
        );
        await pilote.poser(duree: const Duration(seconds: 3));

        // --- L'emploi du temps: le geste central.
        if (await pilote.ouvrirLeModule(
          'timetable',
          sousTitre: 'L\'emploi du temps se compose depuis l\'application.',
        )) {
          await pilote.soulignerLaCle(
            'edt-generer',
            texte: 'La grille se génère, elle ne se saisit pas à la main.',
          );

          if (await pilote.appuyerSurLaCle('edt-generer')) {
            // Simuler d'abord: on ne verse pas des centaines de créneaux en
            // base sans avoir vu ce qu'ils donnent. C'est la règle de l'écran,
            // et le chapitre la montre dans cet ordre.
            pilote.journal.dire(
              'D\'abord simuler : on regarde avant d\'écrire.',
              duree: const Duration(seconds: 5),
            );
            if (await pilote.appuyerSurLaCle(
              'edt-simuler',
              apres: const Duration(seconds: 4),
            )) {
              await pilote.attendreLeTexte('placée');
              pilote.journal.dire(
                'Le serveur place les séances et dit ce qu\'il n\'a pas pu placer.',
                duree: const Duration(seconds: 5),
              );
            }

            if (await pilote.appuyerSurLaCle(
              'edt-appliquer',
              apres: const Duration(seconds: 5),
            )) {
              pilote.journal.dire(
                'Appliqué : la grille de la classe se remplit.',
                duree: const Duration(seconds: 5),
              );
            }
            await pilote.poser(duree: const Duration(seconds: 3));
          }

          // La classe laissée en brouillon par le décor: il reste quelque
          // chose à publier, et c'est ce geste-là qu'on filme.
          await pilote.soulignerLaCle(
            'edt-publier-verrouille',
            texte: 'Publier ouvre la grille aux familles, et la verrouille.',
          );
          await pilote.appuyerSurLaCle(
            'edt-publier-verrouille',
            apres: const Duration(seconds: 3),
          );
        }

        // --- Les examens: la publication classe par classe.
        if (await pilote.ouvrirLeModule(
          'exams',
          sousTitre:
              'Les copies reviennent classe par classe : la publication aussi.',
        )) {
          await pilote.ouvrirLOnglet('Campagnes');
          await pilote.poser();
          await pilote.ouvrirLOnglet('Calendrier');
          pilote.journal.dire(
            'Chaque épreuve dit où en est sa correction.',
            duree: const Duration(seconds: 5),
          );
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        // --- Les notes: arrêter une période.
        if (await pilote.ouvrirLeModule(
          'grades',
          sousTitre: 'Arrêter une période fige les notes et les rangs.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        // --- La communication: le public d'une annonce.
        if (await pilote.ouvrirLeModule(
          'communication',
          sousTitre:
              'Une annonce s\'adresse à un public, et à lui seul.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        // --- Les rapports: ce que l'école délivre.
        if (await pilote.ouvrirLeModule(
          'reports',
          sousTitre: 'Reçus, registres et exports, au même endroit.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
