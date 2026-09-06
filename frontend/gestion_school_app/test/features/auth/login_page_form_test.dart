/// Ce que le formulaire de connexion garantit a l'utilisateur.
///
/// Les erreurs ne vivaient qu'en SnackBar, jamais rattachees au champ fautif,
/// et rien n'empechait d'envoyer deux champs vides au serveur. Les
/// identifiants ne se remplissaient pas non plus tout seuls: sans
/// `autofillHints`, ni le navigateur ni Android ne proposent de les
/// enregistrer.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/features/auth/presentation/login_page.dart';
import 'package:gestion_school_app/features/auth/presentation/widgets/login_form_card.dart';

const _etablissementJson = {
  'id': 4,
  'name': 'Complexe Scolaire Omar Bah (CSOB)',
  'address': 'LTOB (1er etage)',
  'phone': '78 32 59 13 / 66 74 22 32',
  'email': 'contact@csob.ml',
};

/// Un etablissement dont on ne sait pas comment joindre l'administration.
const _etablissementSansContact = {
  'id': 7,
  'name': 'École de Brousse',
  'address': '',
};

class _Transport implements HttpClientAdapter {
  /// Ce que le serveur repond a `/auth/login/`, appel apres appel.
  final List<int> codesLogin;
  final List<String> chemins = [];
  int _appelsLogin = 0;

  _Transport({this.codesLogin = const []});

  int get appelsLogin => _appelsLogin;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);

    if (options.path.contains('/auth/login/')) {
      final code = codesLogin.isEmpty
          ? 401
          : codesLogin[_appelsLogin.clamp(0, codesLogin.length - 1)];
      _appelsLogin++;
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: code,
        ),
      );
    }

    return ResponseBody.fromString(
      jsonEncode(const {'count': 0, 'results': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// `pumpAndSettle` est inutilisable ici: les halos du fond bouclent sans fin.
Future<void> _avancer(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<_Transport> _monter(
  WidgetTester tester, {
  Size taille = const Size(1280, 900),
  List<int> codesLogin = const [],
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(codesLogin: codesLogin);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: LoginPage()),
    ),
  );
  await _avancer(tester);
  return transport;
}

Future<void> _seConnecter(
  WidgetTester tester, {
  String identifiant = 'directeur',
  String motDePasse = 'Password@123',
}) async {
  await tester.enterText(find.byKey(kChampIdentifiant), identifiant);
  await tester.enterText(find.byKey(kChampMotDePasse), motDePasse);
  await tester.tap(find.text('Se connecter'));
  await _avancer(tester);
}

void main() {
  setUp(() {
    // Le cache memoire de TokenStorage est statique: sans cette purge, le
    // premier etablissement lu vaudrait pour tous les cas du fichier.
    TokenStorage.purgerCacheMemoire();
    FlutterSecureStorage.setMockInitialValues({
      'selected_etablissement': jsonEncode(_etablissementJson),
    });
  });

  testWidgets('un formulaire vide ne part pas au serveur', (tester) async {
    final transport = await _monter(tester);

    await tester.tap(find.text('Se connecter'));
    await _avancer(tester);

    expect(transport.appelsLogin, 0);
    expect(find.text('Saisissez votre nom d\'utilisateur.'), findsOneWidget);
    expect(find.text('Saisissez votre mot de passe.'), findsOneWidget);
  });

  testWidgets('des identifiants refuses s_affichent sous le champ', (
    tester,
  ) async {
    await _monter(tester, codesLogin: const [401]);

    await _seConnecter(tester);

    // Le message vit dans le champ, pas dans un bandeau fugace en bas
    // d'ecran: c'est la que l'utilisateur regarde en corrigeant.
    expect(
      find.descendant(
        of: find.byKey(kChampMotDePasse),
        matching: find.text(
          'Identifiants invalides. Vérifiez le nom utilisateur et le mot de passe.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('retaper efface le message du serveur', (tester) async {
    await _monter(tester, codesLogin: const [401]);
    await _seConnecter(tester);

    await tester.enterText(find.byKey(kChampMotDePasse), 'autre-essai');
    await _avancer(tester);

    expect(
      find.textContaining('Identifiants invalides'),
      findsNothing,
    );
  });

  testWidgets('reessayer sans rien retaper relance bien l_appel', (
    tester,
  ) async {
    // Le piege de ce formulaire: si le message d'erreur precedent survit a la
    // resoumission, les validators le retournent encore, la validation echoue
    // et plus aucune requete ne part. Un serveur momentanement tombe puis
    // revenu laisserait l'utilisateur devant un formulaire definitivement
    // mort.
    final transport = await _monter(tester, codesLogin: const [401, 401]);
    await _seConnecter(tester);

    await tester.tap(find.text('Se connecter'));
    await _avancer(tester);

    expect(transport.appelsLogin, 2);
  });

  testWidgets('un refus de compte ne vise aucun champ', (tester) async {
    await _monter(tester, codesLogin: const [403]);

    await _seConnecter(tester);

    const message =
        'Accès refusé. Votre compte n\'est pas autorisé à se connecter.';
    expect(find.text(message), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(kChampMotDePasse),
        matching: find.text(message),
      ),
      findsNothing,
    );
  });

  testWidgets('les deux champs se remplissent automatiquement', (tester) async {
    await _monter(tester);

    expect(find.byType(AutofillGroup), findsOneWidget);
    final identifiant = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(kChampIdentifiant),
        matching: find.byType(TextField),
      ),
    );
    final motDePasse = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(kChampMotDePasse),
        matching: find.byType(TextField),
      ),
    );

    expect(identifiant.autofillHints, contains(AutofillHints.username));
    expect(motDePasse.autofillHints, contains(AutofillHints.password));
  });

  group('les reglages techniques restent atteignables', () {
    // Ils ont quitte le corps de la carte; ils ne doivent pas avoir quitte
    // l'application. Deux tailles, car le bouton change d'ancrage.
    for (final taille in const [Size(1280, 900), Size(360, 640)]) {
      testWidgets('${taille.width.toInt()}x${taille.height.toInt()}', (
        tester,
      ) async {
        await _monter(tester, taille: taille);

        await tester.tap(find.byTooltip('Réglages techniques'));
        await _avancer(tester);

        expect(find.text('Réglages techniques'), findsOneWidget);
        expect(find.text('Tester la connexion'), findsOneWidget);
        expect(find.text('Changer d\'établissement'), findsOneWidget);
      });
    }
  });

  testWidgets('mot de passe oublie donne un contact, pas un formulaire', (
    tester,
  ) async {
    await _monter(tester);

    await tester.tap(find.text('Mot de passe oublié ?'));
    await _avancer(tester);

    expect(find.text('78 32 59 13 / 66 74 22 32'), findsOneWidget);
    expect(find.text('contact@csob.ml'), findsOneWidget);
    // L'assertion qui compte: le serveur n'a pas de reinitialisation en libre
    // service, donc aucun champ ne doit laisser croire qu'une demande part
    // quelque part.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );
  });

  testWidgets('sans coordonnees, il dit ou aller quand meme', (tester) async {
    TokenStorage.purgerCacheMemoire();
    FlutterSecureStorage.setMockInitialValues({
      'selected_etablissement': jsonEncode(_etablissementSansContact),
    });
    await _monter(tester);

    await tester.tap(find.text('Mot de passe oublié ?'));
    await _avancer(tester);

    expect(find.textContaining('secrétariat'), findsOneWidget);
  });
}
