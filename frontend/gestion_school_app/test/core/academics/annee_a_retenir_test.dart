import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/academics/annee_a_retenir.dart';

/// L'année qu'un écran présente par défaut.
///
/// Cinq écrans retenaient `annees.first`, la première ligne servie par l'API,
/// alors qu'aucun ordre n'était défini. Le jour où ce hasard a désigné l'année
/// suivante, « Notes & Bulletins » a répondu « Aucune note enregistrée » sur
/// une base qui en comptait soixante-huit mille, et les bulletins imprimés
/// portaient des tirets partout.
void main() {
  group('anneeARetenir', () {
    test('retient l’année active, où qu’elle soit dans la liste', () {
      final annees = [
        {'id': 7, 'name': '2026-2027', 'is_active': false, 'start_date': '2026-09-01'},
        {'id': 3, 'name': '2025-2026', 'is_active': true, 'start_date': '2025-09-01'},
      ];

      expect(anneeARetenir(annees), 3);
    });

    test('le défaut ne dépend pas de l’ordre de la liste', () {
      final active = {'id': 3, 'is_active': true, 'start_date': '2025-09-01'};
      final suivante = {'id': 7, 'is_active': false, 'start_date': '2026-09-01'};

      expect(anneeARetenir([active, suivante]), anneeARetenir([suivante, active]));
    });

    test('sans année active, retient la plus récente', () {
      final annees = [
        {'id': 1, 'is_active': false, 'start_date': '2024-09-01'},
        {'id': 2, 'is_active': false, 'start_date': '2026-09-01'},
        {'id': 3, 'is_active': false, 'start_date': '2025-09-01'},
      ];

      expect(anneeARetenir(annees), 2);
    });

    test('sans date exploitable, ne plante pas et rend quelque chose', () {
      final annees = [
        {'id': 4, 'is_active': false},
        {'id': 5, 'is_active': false, 'start_date': ''},
      ];

      expect(anneeARetenir(annees), 4);
    });

    test('rend null sur une liste vide', () {
      expect(anneeARetenir(const []), isNull);
    });

    test('rend null quand l’identifiant est absent ou nul', () {
      expect(anneeARetenir([{'is_active': true}]), isNull);
      expect(anneeARetenir([{'id': 0, 'is_active': true}]), isNull);
    });

    test('accepte un identifiant rendu sous forme de texte', () {
      expect(anneeARetenir([{'id': '9', 'is_active': true}]), 9);
    });
  });

  group('ligneDeLAnneeARetenir', () {
    test('rend la ligne entière, pour son nom et ses dates', () {
      final annees = [
        {'id': 7, 'name': '2026-2027', 'is_active': false},
        {'id': 3, 'name': '2025-2026', 'is_active': true},
      ];

      expect(ligneDeLAnneeARetenir(annees)?['name'], '2025-2026');
    });

    test('rend null sur une liste vide', () {
      expect(ligneDeLAnneeARetenir(const []), isNull);
    });
  });
}
