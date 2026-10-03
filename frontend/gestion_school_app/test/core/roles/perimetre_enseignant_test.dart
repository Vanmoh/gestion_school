import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/roles/perimetre_enseignant.dart';

/// Comment un enseignant obtient sa fiche et ses affectations.
///
/// Le module « teachers » lui est fermé : `/teachers/` et
/// `/teacher-assignments/` lui répondent 403. Cinq écrans les réclamaient
/// quand même, avalaient le refus, et concluaient qu'il n'enseignait nulle
/// part — « Classes 0 » pour une enseignante affectée à deux matières.
void main() {
  group('routes selon le rôle', () {
    test('l’enseignant passe par ses propres routes', () {
      expect(routeDeLaFicheEnseignant('teacher'), '/teachers/mon-profil/');
      expect(
        routeDesAffectations('teacher'),
        '/teacher-assignments/mes-affectations/',
      );
    });

    test('les autres rôles gardent l’annuaire', () {
      for (final role in ['director', 'censor', 'super_admin', 'accountant']) {
        expect(routeDeLaFicheEnseignant(role), '/teachers/');
        expect(routeDesAffectations(role), '/teacher-assignments/');
      }
    });

    test('un rôle inconnu ou absent garde l’annuaire', () {
      // Le serveur tranche de toute façon: mieux vaut un 403 explicite qu'une
      // route réservée appelée par quelqu'un qui n'y a pas sa place.
      expect(routeDeLaFicheEnseignant(null), '/teachers/');
      expect(routeDeLaFicheEnseignant('inconnu'), '/teachers/');
    });

    test('estEnseignant ne reconnaît que le rôle exact', () {
      expect(estEnseignant('teacher'), isTrue);
      expect(estEnseignant('Teacher'), isFalse);
      expect(estEnseignant(null), isFalse);
    });
  });

  group('lignesDeLaFiche', () {
    test('un objet seul devient une liste d’une ligne', () {
      final lignes = lignesDeLaFiche({'id': 107, 'user': 42});

      expect(lignes, hasLength(1));
      expect(lignes.first['id'], 107);
    });

    test('une réponse paginée rend ses résultats', () {
      final lignes = lignesDeLaFiche({
        'count': 2,
        'results': [
          {'id': 1},
          {'id': 2},
        ],
      });

      expect(lignes.map((l) => l['id']), [1, 2]);
    });

    test('une liste nue passe telle quelle', () {
      expect(
        lignesDeLaFiche([
          {'id': 3},
        ]).first['id'],
        3,
      );
    });

    test('rien d’exploitable rend une liste vide, jamais une exception', () {
      // Un écran qui appelle avant de savoir qui il sert ne doit pas tomber.
      expect(lignesDeLaFiche(null), isEmpty);
      expect(lignesDeLaFiche('erreur'), isEmpty);
      expect(lignesDeLaFiche(const <String, dynamic>{}), isEmpty);
    });
  });
}
