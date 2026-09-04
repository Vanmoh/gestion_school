/// Le parcours complet de « Enseignants »: chercher, choisir, agir.
///
/// La page parle a l'API sans passer par un repository: on lui substitue donc
/// le transport de Dio, ce qui fait tourner le vrai cablage -- chargement,
/// filtrage local, selection, fiche.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/teachers/presentation/teachers_page.dart';
import 'package:gestion_school_app/features/teachers/presentation/widgets/teacher_palette_card.dart';

/// Transport de substitution: repond depuis une table, sans reseau.
class _FauxTransport implements HttpClientAdapter {
  final Map<String, dynamic> reponses;
  final List<String> appels = [];

  _FauxTransport(this.reponses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    appels.add(options.path);
    final corps = reponses[options.path] ?? const [];
    return ResponseBody.fromString(
      jsonEncode(corps),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _user(int id, String nom, {String tel = ''}) => {
  'id': id,
  'full_name': nom,
  'first_name': nom.split(' ').first,
  'last_name': nom.split(' ').last,
  'username': nom.toLowerCase().replaceAll(' ', '.'),
  'email': '${nom.toLowerCase().replaceAll(' ', '.')}@ecole.test',
  'phone': tel,
};

Map<String, dynamic> _profil(int id, int userId, String code) => {
  'id': id,
  'user': userId,
  'employee_code': code,
  'hire_date': '2024-09-01',
  'user_full_name': 'x',
};

final _reponses = <String, dynamic>{
  '/auth/users/directory/': [
    _user(1, 'Amadou Diallo', tel: '76112233'),
    _user(2, 'Fatou Keita'),
    _user(3, 'Moussa Traore'),
  ],
  '/teachers/': [
    _profil(10, 1, 'ENS-001'),
    _profil(11, 2, 'ENS-002'),
  ],
  '/subjects/': [
    {'id': 100, 'name': 'Mathématiques'},
  ],
  '/classrooms/': [
    {'id': 200, 'name': '6A'},
  ],
  '/teacher-assignments/': [
    {
      'id': 300,
      'teacher': 10,
      'subject': 100,
      'classroom': 200,
      'subject_name': 'Mathématiques',
      'classroom_name': '6A',
    },
  ],
};

ModulePermissions _droits(AccessLevel niveau, {bool exports = true}) {
  return ModulePermissions(
    role: 'director',
    // La liste des enseignants est un export nominatif: elle depend d'une
    // capacite, et non du seul niveau d'acces au module. Sans elle, le bouton
    // ne s'affiche pas -- ce qui est le comportement voulu, mais laissait le
    // test chercher un bouton qu'il n'avait pas demande.
    capabilities: {Capacites.exportsSensibles: exports},
    modules: {
      'teachers': ModulePermission(
        key: 'teachers',
        label: 'Enseignants',
        group: 'pedagogie',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<_FauxTransport> _pumpPage(
  WidgetTester tester, {
  AccessLevel niveau = AccessLevel.write,
  bool exports = true,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final transport = _FauxTransport(_reponses);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(
          _droits(niveau, exports: exports),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: TeachersPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return transport;
}

Future<void> _chercher(WidgetTester tester, String texte) async {
  await tester.enterText(find.byType(TextField).first, texte);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('au chargement, l_ecran invite a chercher', (tester) async {
    await _pumpPage(tester);

    // Regression: le premier enseignant etait selectionne d'office, et cette
    // selection se faisait pendant le build.
    expect(find.byType(TeacherPaletteCard), findsNothing);
    expect(find.textContaining('Recherchez un enseignant'), findsOneWidget);
  });

  testWidgets('la page interroge bien les cinq sources', (tester) async {
    final transport = await _pumpPage(tester);

    expect(
      transport.appels,
      containsAll([
        '/auth/users/directory/',
        '/teachers/',
        '/subjects/',
        '/classrooms/',
        '/teacher-assignments/',
      ]),
    );
  });

  testWidgets('une seule correspondance ouvre directement sa fiche', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _chercher(tester, 'amadou');

    // Regression: l'ecran annoncait « aucun enseignant ne correspond » alors
    // qu'il venait d'en trouver un -- la carte des resultats exige plusieurs
    // correspondances, la fiche exige une selection, et rien ne comblait
    // l'entre-deux.
    expect(find.byType(TeacherPaletteCard), findsOneWidget);
    expect(find.textContaining('Aucun enseignant ne correspond'), findsNothing);
  });

  testWidgets('plusieurs correspondances demandent lequel ouvrir', (
    tester,
  ) async {
    await _pumpPage(tester);

    // « a » figure dans Amadou, Fatou et Moussa Traore.
    await _chercher(tester, 'a');

    expect(find.byType(TeacherPaletteCard), findsNothing);
    expect(find.textContaining('correspondent'), findsOneWidget);
  });

  testWidgets('chercher par matiere trouve celui qui l_enseigne', (
    tester,
  ) async {
    await _pumpPage(tester);

    // « Qui fait maths en 6A ? » est la question posee en salle des profs.
    await _chercher(tester, 'mathémat');

    expect(find.byType(TeacherPaletteCard), findsOneWidget);
    expect(find.text('Amadou Diallo'), findsWidgets);
  });

  testWidgets('chercher par classe aussi', (tester) async {
    await _pumpPage(tester);

    await _chercher(tester, '6A');

    expect(find.byType(TeacherPaletteCard), findsOneWidget);
  });

  testWidgets('un compte sans profil reste trouvable', (tester) async {
    await _pumpPage(tester);

    // Moussa n'a pas de profil enseignant: c'est justement celui qu'on cherche
    // pour lui en creer un. Une recherche serveur ne le verrait pas.
    await _chercher(tester, 'moussa');

    expect(find.byType(TeacherPaletteCard), findsOneWidget);
    expect(find.text('Moussa Traore'), findsWidgets);
  });

  testWidgets('une recherche sans reponse le dit avec les mots saisis', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _chercher(tester, 'zzzz');

    expect(
      find.textContaining('Aucun enseignant ne correspond'),
      findsOneWidget,
    );
    expect(find.byType(TeacherPaletteCard), findsNothing);
  });

  testWidgets('effacer la recherche referme la fiche', (tester) async {
    await _pumpPage(tester);
    await _chercher(tester, 'amadou');
    expect(find.byType(TeacherPaletteCard), findsOneWidget);

    await tester.tap(find.byTooltip('Effacer'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TeacherPaletteCard), findsNothing);
    expect(find.textContaining('Recherchez un enseignant'), findsOneWidget);
  });

  testWidgets('la page ne porte plus de listes deroulantes de selection', (
    tester,
  ) async {
    await _pumpPage(tester);

    // Deux menus deroulants servaient a choisir l'enseignant; leur retour
    // signalerait une regression de la refonte.
    expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
    expect(find.text('Liste des enseignants'), findsOneWidget);
  });

  testWidgets('sans droit d_export, la liste imprimable n_est pas proposee', (
    tester,
  ) async {
    // Le PDF nomme chaque agent et porte ses coordonnees. Le censeur et le
    // promoteur lisent la fiche enseignant sans pouvoir en sortir ce fichier:
    // le bouton s'affichait pour eux et le serveur le refusait au clic.
    await _pumpPage(tester, exports: false);

    expect(find.text('Liste des enseignants'), findsNothing);
    // Le reste de l'ecran ne bouge pas: c'est un bouton en moins, pas un
    // module ferme.
    expect(find.textContaining('Recherchez un enseignant'), findsOneWidget);
  });

  testWidgets('un bouton permet d_ajouter un enseignant inexistant', (
    tester,
  ) async {
    await _pumpPage(tester);

    // Inscrire quelqu'un qui n'existe pas encore demandait d'ouvrir « Gérer
    // enseignant », d'y trouver la creation de compte, puis le profil: trois
    // niveaux derriere un libelle qui ne dit pas « ajouter ».
    expect(find.text('Ajouter enseignant'), findsOneWidget);

    final bouton = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Ajouter enseignant'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(bouton.onPressed, isNotNull);
  });

  testWidgets('en lecture seule, Ajouter enseignant est grise et motive', (
    tester,
  ) async {
    await _pumpPage(tester, niveau: AccessLevel.read);

    final bouton = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Ajouter enseignant'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(bouton.onPressed, isNull);

    final infobulle = tester.widget<Tooltip>(
      find.ancestor(
        of: find.text('Ajouter enseignant'),
        matching: find.byType(Tooltip),
      ),
    );
    expect(infobulle.message, contains('sans les modifier'));
  });

  testWidgets('le bouton ouvre la creation de compte enseignant', (
    tester,
  ) async {
    await _pumpPage(tester);

    await tester.tap(find.text('Ajouter enseignant'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Le dialogue enchaine ensuite sur le profil: c'est le parcours complet
    // d'un enseignant qui n'existe pas encore.
    expect(find.byType(Dialog), findsWidgets);
  });

  testWidgets('la remuneration n_apparait jamais dans la fiche', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _chercher(tester, 'amadou');

    // Le module est ouvert en lecture au censeur et au surveillant: les
    // montants restent dans Paie.
    for (final interdit in ['Salaire', 'salary', 'Taux horaire', 'F/h']) {
      expect(find.textContaining(interdit), findsNothing, reason: interdit);
    }
  });
}
