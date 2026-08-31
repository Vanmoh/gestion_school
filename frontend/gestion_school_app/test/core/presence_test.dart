/// La présence côté écran: qui est là maintenant, et depuis quand on ne l'a
/// plus vu.
///
/// Le défaut corrigé ici se voyait à l'œil nu: un correspondant restait « en
/// ligne » des jours après sa dernière visite. L'écran recevait un booléen,
/// le posait, et rien ne le faisait jamais redescendre — ni la fermeture
/// brutale d'un navigateur, ni un serveur redémarré.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/models/presence.dart';

void main() {
  group('Presence', () {
    test('un signe de vie recent vaut en ligne', () {
      final presence = Presence(
        vuA: DateTime.now().subtract(const Duration(seconds: 20)),
      );

      expect(presence.enLigne(), isTrue);
      expect(presence.libelle(), 'En ligne');
    });

    test('passe la fenetre, la presence perime d_elle-meme', () {
      final maintenant = DateTime(2026, 8, 31, 14, 32);
      final presence = Presence(
        // Le serveur disait « en ligne » quand il a repondu; deux minutes ont
        // passe depuis, et personne n'a redit le contraire.
        vuA: maintenant.subtract(const Duration(minutes: 2)),
        annonceEnLigne: true,
      );

      expect(presence.enLigne(maintenant: maintenant), isFalse);
      expect(
        presence.libelle(maintenant: maintenant),
        'Vu aujourd’hui à 14:30',
      );
    });

    test('jamais vue: ni en ligne ni datee', () {
      const presence = Presence();

      expect(presence.jamaisVue, isTrue);
      expect(presence.enLigne(), isFalse);
      expect(presence.libelle(), 'Jamais connecté');
    });

    test('sans horodatage, la parole du serveur fait foi', () {
      // Serveur anterieur, qui n'envoyait que `online`.
      const presence = Presence(annonceEnLigne: true);

      expect(presence.enLigne(), isTrue);
    });

    test('une horloge locale en avance ne declare pas l_autre parti', () {
      final presence = Presence(
        vuA: DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(presence.enLigne(), isTrue);
    });

    test('la charge du serveur se lit telle quelle', () {
      final presence = Presence.depuisJson({
        'online': true,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      });

      expect(presence.enLigne(), isTrue);
      expect(presence.jamaisVue, isFalse);
    });
  });

  group('dateHeureLisible', () {
    final maintenant = DateTime(2026, 8, 31, 14, 32);

    test('le jour meme, l_heure suffit', () {
      expect(
        dateHeureLisible(DateTime(2026, 8, 31, 8, 5), maintenant: maintenant),
        'aujourd’hui à 08:05',
      );
    });

    test('la veille se nomme', () {
      expect(
        dateHeureLisible(DateTime(2026, 8, 30, 22, 15), maintenant: maintenant),
        'hier à 22:15',
      );
    });

    test('au-dela, la date complete avec l_heure et la minute', () {
      // Sans l'heure, deux visites du meme jour ne se departagent pas.
      expect(
        dateHeureLisible(DateTime(2026, 8, 12, 9, 7), maintenant: maintenant),
        'le 12/08/2026 à 09:07',
      );
    });
  });
}
