/// Ce que la famille voit des examens, et ce qu'elle ne voit plus.
///
/// Elle recevait l'écran d'administration entier, seulement grisé : cinq
/// formulaires de création inertes, le calendrier de toutes les classes, le
/// tableau des surveillants, et le compte des notes saisies mais non
/// publiées — l'existence même des notes que l'école lui refusait de lire.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/exams/domain/exam_models.dart';
import 'package:gestion_school_app/features/exams/domain/parent_exam_grouping.dart';

ExamResultItem _note({
  required int id,
  required int studentId,
  String enfant = 'Awa Traoré',
  String matricule = 'LEMB1EM125E0001F',
  String matiere = 'Mathématiques',
  String session = 'Composition du premier trimestre',
  String periode = 'T1',
  double score = 15,
}) {
  return ExamResultItem(
    id: id,
    sessionId: 1,
    studentId: studentId,
    subjectId: 1,
    score: score,
    subjectName: matiere,
    sessionTitle: session,
    sessionTerm: periode,
    studentFullName: enfant,
    studentMatricule: matricule,
  );
}

ExamPlanningItem _epreuve({required int id, required String date}) {
  return ExamPlanningItem(
    id: id,
    sessionId: 1,
    classroomId: 1,
    subjectId: 1,
    examDate: date,
    startTime: '08:00',
    endTime: '10:00',
  );
}

void main() {
  group('regroupement par enfant', () {
    test('un parent de deux enfants lit deux blocs, dans l_ordre des noms', () {
      final groupes = grouperLesExamensParEnfant([
        _note(id: 1, studentId: 2, enfant: 'Modibo Keita', matricule: 'M2'),
        _note(id: 2, studentId: 1, enfant: 'Awa Traoré', matricule: 'A1'),
      ]);

      expect(groupes.map((g) => g.nomDeLEnfant), ['Awa Traoré', 'Modibo Keita']);
    });

    test('les notes d_un enfant vont de la plus recente a la plus ancienne', () {
      final groupes = grouperLesExamensParEnfant([
        _note(id: 1, studentId: 1, matiere: 'Français'),
        _note(id: 5, studentId: 1, matiere: 'Mathématiques'),
      ]);

      expect(
        groupes.single.resultats.map((r) => r.matiere),
        ['Mathématiques', 'Français'],
      );
    });

    test('un nom manquant sur une ligne n_efface pas celui des autres', () {
      // Le serveur peut rendre une ligne sans libellé; garder le premier non
      // vide évite qu'un bloc entier s'intitule « Élève ».
      final groupes = grouperLesExamensParEnfant([
        _note(id: 1, studentId: 1, enfant: '', matricule: ''),
        _note(id: 2, studentId: 1, enfant: 'Awa Traoré', matricule: 'A1'),
      ]);

      expect(groupes.single.nomDeLEnfant, 'Awa Traoré');
      expect(groupes.single.matricule, 'A1');
    });

    test('sans aucun nom, le bloc reste nommable', () {
      final groupes = grouperLesExamensParEnfant([
        _note(id: 1, studentId: 1, enfant: '', matricule: ''),
      ]);

      expect(groupes.single.nomDeLEnfant, 'Élève');
    });

    test('la moyenne ne porte que sur ce qui est affiche', () {
      // Le serveur ne transmet que les notes publiées : annoncer une moyenne
      // qui en contiendrait d'autres donnerait un chiffre que la famille ne
      // peut pas retrouver ligne à ligne.
      final groupes = grouperLesExamensParEnfant([
        _note(id: 1, studentId: 1, score: 12),
        _note(id: 2, studentId: 1, score: 16),
      ]);

      expect(groupes.single.moyenne, 14);
    });

    test('sans note, il n_y a pas de moyenne a montrer', () {
      final groupe = GroupeDExamensParEnfant(
        studentId: 1,
        nomDeLEnfant: 'Awa',
        matricule: 'A1',
        resultats: const [],
      );

      expect(groupe.moyenne, isNull);
    });
  });

  group('epreuves a venir', () {
    final aujourdHui = DateTime(2026, 1, 15);

    test('celles d_hier ne figurent plus au calendrier', () {
      final futures = epreuvesAVenir([
        _epreuve(id: 1, date: '2026-01-10'),
        _epreuve(id: 2, date: '2026-01-20'),
      ], aujourdHui);

      expect(futures.map((e) => e.id), [2]);
    });

    test('celle du jour compte encore', () {
      // Une épreuve de l'après-midi ne doit pas disparaître le matin même.
      final futures = epreuvesAVenir([
        _epreuve(id: 1, date: '2026-01-15'),
      ], aujourdHui);

      expect(futures.map((e) => e.id), [1]);
    });

    test('la plus proche vient en premier', () {
      final futures = epreuvesAVenir([
        _epreuve(id: 1, date: '2026-02-01'),
        _epreuve(id: 2, date: '2026-01-20'),
      ], aujourdHui);

      expect(futures.map((e) => e.id), [2, 1]);
    });

    test('une date illisible ne fait pas disparaitre une epreuve', () {
      // Mieux vaut une ligne mal datée qu'une épreuve absente du calendrier
      // d'une famille.
      final futures = epreuvesAVenir([
        _epreuve(id: 1, date: 'a-venir'),
      ], aujourdHui);

      expect(futures.map((e) => e.id), [1]);
    });
  });

  group('libelles d_une note', () {
    test('la matiere est nommee, pas numerotee', () {
      expect(_note(id: 1, studentId: 1).matiere, 'Mathématiques');
    });

    test('sans libelle, on n_affiche pas un identifiant nu', () {
      expect(_note(id: 1, studentId: 1, matiere: '').matiere, 'Matière');
    });

    test('l_epreuve porte son titre et sa periode', () {
      expect(
        _note(id: 1, studentId: 1).epreuve,
        'Composition du premier trimestre • T1',
      );
    });

    test('sans titre, la periode suffit', () {
      expect(_note(id: 1, studentId: 1, session: '').epreuve, 'T1');
    });

    test('sans rien, la ligne reste lisible', () {
      expect(
        _note(id: 1, studentId: 1, session: '', periode: '').epreuve,
        'Examen',
      );
    });
  });
}
