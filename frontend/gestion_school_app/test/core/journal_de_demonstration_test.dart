/// Le canal entre le pilote de démonstration et le montage.
///
/// Le pilote joue l'application pendant qu'un enregistreur filme l'écran ; le
/// montage, lui, doit savoir à quelle seconde poser un carton, un sous-titre ou
/// un encadré, et où dessiner cet encadré. Ce journal est ce canal, et rien
/// d'autre ne le vérifie : les prises elles-mêmes n'existent que sur un
/// appareil connecté, que l'on n'a pas toujours sous la main.
///
/// D'où ce fichier : la logique du journal a été sortie de `integration_test/`
/// exprès pour être éprouvée comme n'importe quel autre code.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/demonstration/journal_de_demonstration.dart';

/// Une horloge qui avance à la demande: un test ne peut pas attendre de vraies
/// secondes, et le journal date chaque événement.
class _Horloge {
  DateTime _instant = DateTime.utc(2026, 1, 12, 8, 30);

  DateTime maintenant() => _instant;

  void avancerDe(Duration duree) => _instant = _instant.add(duree);
}

void main() {
  group('Le journal d_une prise', () {
    test('il date chaque evenement dans l_ordre du tournage', () {
      final horloge = _Horloge();
      final journal = JournalDeDemonstration(horloge: horloge.maintenant);

      journal.ouvrirLeChapitre('director', 'DIRECTEUR');
      horloge.avancerDe(const Duration(seconds: 12));
      journal.dire('La grille se génère.');
      horloge.avancerDe(const Duration(seconds: 5));
      journal.clore();

      final dates = journal.evenements.map((e) => e.quand).toList();
      expect(dates[1].difference(dates[0]), const Duration(seconds: 12));
      expect(dates[2].difference(dates[1]), const Duration(seconds: 5));
    });

    test('ecrire puis relire ne perd rien', () {
      // Le montage relit ce que la prise a écrit: si le format se perd entre
      // les deux, l'habillage tombe à côté sans que rien ne le signale.
      final journal = JournalDeDemonstration();
      journal.ouvrirLeChapitre('teacher', 'ENSEIGNANT');
      journal.dire('Corriger n\'est pas publier.');
      journal.souligner(
        const CadreDEcran(x: 312, y: 206, largeur: 420, hauteur: 64),
        texte: 'Le bouton Publier lui est fermé.',
      );
      journal.clore();

      final relus = JournalDeDemonstration.relire(journal.enLignesJson());

      expect(relus.length, 4);
      expect(relus.first.genre, GenreDEvenement.chapitre);
      expect(relus.first.role, 'teacher');
      expect(relus[1].texte, 'Corriger n\'est pas publier.');
      expect(relus[2].cadre?.largeur, 420);
      expect(relus.last.genre, GenreDEvenement.fin);
    });

    test('les accents et les apostrophes traversent le format', () {
      // Le montage brûle ces textes dans la vidéo: un accent perdu se voit.
      final journal = JournalDeDemonstration();
      journal.dire('Élèves inscrits — l\'année 2025-2026, « T1 »');

      final relus = JournalDeDemonstration.relire(journal.enLignesJson());

      expect(relus.single.texte, 'Élèves inscrits — l\'année 2025-2026, « T1 »');
    });

    test('une ligne illisible n_emporte pas le reste du journal', () {
      // Une prise interrompue en pleine écriture laisse une ligne tronquée.
      const contenu = '''
{"type":"chapitre","epoch_ms":1000,"texte":"DIRECTEUR","role":"director","duree_ms":3000}
{"type":"sousTitre","epoch_ms":2000,"texte":"tronq
{"type":"fin","epoch_ms":3000,"duree_ms":0}
''';

      final relus = JournalDeDemonstration.relire(contenu);

      expect(relus.length, 2);
      expect(relus.last.genre, GenreDEvenement.fin);
    });

    test('un cadre se decale du haut de la fenetre vers celui de la video', () {
      // La barre de titre GTK est recadrée par la capture: la vue Flutter ne
      // commence pas à l'ordonnée zéro de l'image.
      const cadre = CadreDEcran(x: 10, y: 100, largeur: 200, hauteur: 40);

      final decale = cadre.decaleDe(18);

      expect(decale.y, 118);
      expect(decale.x, 10);
      expect(decale.hauteur, 40);
    });
  });

  group('L_etat d_une prise', () {
    test('une prise close est complete', () {
      final journal = JournalDeDemonstration();
      journal.ouvrirLeChapitre('parent', 'PARENT');
      journal.dire('Il suit son enfant.');
      journal.clore();

      expect(
        JournalDeDemonstration.priseComplete(journal.evenements),
        isTrue,
      );
    });

    test('une prise sans fin est tronquee', () {
      // C'est ce que le montage regarde avant de garder un chapitre: mieux vaut
      // un carton qui dit franchement qu'il manque qu'un chapitre coupé net.
      final journal = JournalDeDemonstration();
      journal.ouvrirLeChapitre('parent', 'PARENT');
      journal.dire('Il suit son enfant.');

      expect(
        JournalDeDemonstration.priseComplete(journal.evenements),
        isFalse,
      );
    });

    test('un journal vide n_est pas une prise', () {
      expect(JournalDeDemonstration.priseComplete(const []), isFalse);
    });

    test('des evenements sans chapitre ne font pas une prise', () {
      final journal = JournalDeDemonstration();
      journal.dire('Une phrase orpheline.');
      journal.clore();

      expect(
        JournalDeDemonstration.priseComplete(journal.evenements),
        isFalse,
      );
    });
  });

  group('Les neuf chapitres', () {
    test('les neuf roles de l_application y figurent une fois chacun', () {
      // Le montage lit cette table sans exécuter les pilotes: un rôle manquant
      // produirait une vidéo qui saute un chapitre sans faire rougir la CI.
      const rolesDeLApplication = {
        'super_admin',
        'promoter',
        'director',
        'censor',
        'accountant',
        'supervisor',
        'teacher',
        'parent',
        'student',
      };

      final declares = chapitresDeLaDemonstration.map((c) => c.role).toList();

      expect(declares.toSet(), rolesDeLApplication);
      expect(declares.length, rolesDeLApplication.length);
    });

    test('les rangs vont de un a neuf, sans trou', () {
      final rangs = chapitresDeLaDemonstration.map((c) => c.rang).toList();

      expect(rangs, List<int>.generate(9, (index) => index + 1));
    });

    test('chaque chapitre porte un titre et une mission', () {
      for (final chapitre in chapitresDeLaDemonstration) {
        expect(chapitre.titre.trim(), isNotEmpty, reason: chapitre.role);
        expect(chapitre.mission.trim(), isNotEmpty, reason: chapitre.role);
      }
    });
  });
}
