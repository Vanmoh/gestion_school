/// Les accès rendus aux familles qui n'avaient jamais pu entrer.
///
/// Les comptes ouverts avant l'application portent un identifiant composé à
/// partir du nom et un mot de passe que personne ne leur a jamais remis. Ce
/// qui se vérifie ici est ce qui rend le geste utilisable : les accès sont
/// lisibles à l'écran, copiables d'un coup, et ce qui n'a pas bougé est dit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/users/domain/acces_rouverts.dart';
import 'package:gestion_school_app/features/users/presentation/widgets/dialogue_acces_rouverts.dart';

const _reponse = <String, dynamic>{
  'comptes': [
    {
      'eleve': 'Ousmane Bagayoko',
      'matricule': 'IO1EM125E0028M',
      'classe': '1ère Année EM1',
      'identifiant': 'ousmane.bagayoko',
      'mot_de_passe': 'IO1EM125E0028M',
      'parent': 'Bakary Sangare',
      'parent_identifiant': 'bakary.sangare',
      'parent_mot_de_passe': '73658334',
    },
    {
      'eleve': 'Awa Bagayoko',
      'matricule': 'IO1EM125E0029F',
      'classe': '1ère Année EM1',
      'identifiant': 'awa.bagayoko',
      'mot_de_passe': 'IO1EM125E0029F',
    },
  ],
  'deja_utilises': 3,
};

Future<void> _ouvrir(WidgetTester tester, AccesRouverts acces) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DialogueAccesRouverts(acces: acces, classe: '1ère Année EM1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('lecture de la reponse', () {
    test('les deux accès d_une famille se lisent', () {
      final acces = AccesRouverts.fromJson(_reponse);

      expect(acces.comptes, hasLength(2));
      expect(acces.comptes.first.motDePasse, 'IO1EM125E0028M');
      expect(acces.comptes.first.parentMotDePasse, '73658334');
      expect(acces.dejaUtilises, 3);
    });

    test('un eleve sans parent rouvert ne porte pas de ligne parent', () {
      final acces = AccesRouverts.fromJson(_reponse);

      expect(acces.comptes[1].porteUnParent, isFalse);
    });

    test('une reponse illisible ne fait pas tomber l_ecran', () {
      // Une réponse d'un autre âge, ou une erreur rendue en texte: mieux
      // vaut une fenêtre vide qu'un écran qui tombe sur des accès qu'on
      // vient de poser et qu'on ne pourra plus lire.
      expect(AccesRouverts.fromJson('boum').estVide, isTrue);
      expect(AccesRouverts.fromJson(null).comptes, isEmpty);
    });
  });

  group('la fenetre', () {
    testWidgets('elle montre identifiant et mot de passe de chacun', (
      tester,
    ) async {
      await _ouvrir(tester, AccesRouverts.fromJson(_reponse));

      expect(find.textContaining('ousmane.bagayoko'), findsOneWidget);
      expect(find.textContaining('IO1EM125E0028M'), findsWidgets);
      expect(find.textContaining('bakary.sangare'), findsOneWidget);
      expect(find.textContaining('73658334'), findsOneWidget);
    });

    testWidgets('elle dit ce qui n_a pas bouge', (tester) async {
      // Sans ce compte, une liste plus courte que la classe passerait pour
      // un oubli, et on recommencerait.
      await _ouvrir(tester, AccesRouverts.fromJson(_reponse));

      expect(find.textContaining('3 compte(s)'), findsOneWidget);
    });

    testWidgets('elle previent que les accès ne repasseront pas', (
      tester,
    ) async {
      await _ouvrir(tester, AccesRouverts.fromJson(_reponse));

      expect(find.textContaining('ne s\'afficheront plus'), findsOneWidget);
    });

    testWidgets('rien a rouvrir n_est pas un echec', (tester) async {
      await _ouvrir(
        tester,
        AccesRouverts.fromJson(const {'comptes': [], 'deja_utilises': 12}),
      );

      expect(find.textContaining('servent déjà'), findsOneWidget);
      // Rien à copier: le bouton n'a pas lieu d'être.
      expect(find.byKey(const Key('copier-les-acces')), findsNothing);
    });

    testWidgets('tout se copie d_un coup', (tester) async {
      // Les recopier à la main, ligne par ligne, garantissait qu'une
      // famille reparte avec le mot de passe d'une autre.
      await _ouvrir(tester, AccesRouverts.fromJson(_reponse));

      expect(find.byKey(const Key('copier-les-acces')), findsOneWidget);
    });

    test('le texte copie porte les deux accès de chaque famille', () {
      final widget = DialogueAccesRouverts(
        acces: AccesRouverts.fromJson(_reponse),
        classe: '1ère Année EM1',
      );

      expect(widget.texte, contains('ousmane.bagayoko / IO1EM125E0028M'));
      expect(
        widget.texte,
        contains('Parent Bakary Sangare : bakary.sangare / 73658334'),
      );
      expect(widget.texte, contains('1ère Année EM1'));
    });
  });
}
