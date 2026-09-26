/// L'écran Communication, rangé par destinataire.
///
/// Il empilait trois formulaires et trois listes calqués sur ses trois
/// ViewSets, et cherchait dedans en mémoire. Surtout, son champ « Audience
/// (all, parents, teachers...) » était libre et le serveur ne s'en servait
/// pas: une consigne écrite « teachers » s'affichait chez les familles. Le
/// public se choisit maintenant dans une liste fermée, et c'est ce que ces
/// tests tiennent.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/communication/data/communication_repository.dart';
import 'package:gestion_school_app/features/communication/domain/communication_models.dart';
import 'package:gestion_school_app/features/communication/presentation/communication_controller.dart';
import 'package:gestion_school_app/features/communication/presentation/communication_module_page.dart';

const _annonce = AnnonceItem(
  id: 3,
  titre: 'Remise des copies avant vendredi',
  message: 'Les copies de composition sont attendues au secrétariat.',
  public: PublicDeLAnnonce.enseignants,
  publieeLe: '2026-01-12T08:00:00Z',
);

const _enAttente = NotificationItem(
  id: 11,
  titre: 'Bulletin disponible',
  message: 'Le bulletin du premier trimestre est disponible.',
  canal: CanalDeNotification.sms,
  destinataireId: 40,
  destinataire: 'Awa Traore',
  envoyee: false,
  envoyeeLe: '',
  creeeLe: '2026-01-12T08:00:00Z',
);

const _partie = NotificationItem(
  id: 12,
  titre: 'Absence constatée',
  message: 'Votre enfant était absent ce matin.',
  canal: CanalDeNotification.push,
  destinataireId: 40,
  destinataire: 'Awa Traore',
  envoyee: true,
  envoyeeLe: '2026-01-11T09:30:00Z',
  creeeLe: '2026-01-11T09:00:00Z',
);

class _FauxDepot extends CommunicationRepository {
  final List<AnnonceItem> annonces;
  final List<NotificationItem> notifications;
  final List<PasserelleSmsItem> passerelles;

  /// Ce que l'écran a demandé au serveur: les gestes, et les filtres.
  final List<String> gestes = [];
  final List<String> filtres = [];

  _FauxDepot({
    List<AnnonceItem>? annonces,
    List<NotificationItem>? notifications,
    this.passerelles = const [],
  }) : annonces = annonces ?? const [_annonce],
       notifications = notifications ?? const [_enAttente, _partie],
       super(Dio());

  @override
  Future<List<AnnonceItem>> fetchAnnonces({
    String recherche = '',
    PublicDeLAnnonce? public,
  }) async {
    filtres.add('annonces recherche=$recherche public=${public?.code}');
    return annonces;
  }

  @override
  Future<void> creerAnnonce({
    required String titre,
    required String message,
    required PublicDeLAnnonce public,
  }) async {
    gestes.add('publier:$titre:${public.code}');
  }

  @override
  Future<void> modifierAnnonce({
    required int id,
    String? titre,
    String? message,
    PublicDeLAnnonce? public,
  }) async {
    gestes.add('corriger:$id:${public?.code}');
  }

  @override
  Future<void> supprimerAnnonce(int id) async => gestes.add('retirer-annonce:$id');

  @override
  Future<List<NotificationItem>> fetchNotifications({
    String recherche = '',
    CanalDeNotification? canal,
    bool? envoyees,
  }) async {
    filtres.add(
      'notifications recherche=$recherche canal=${canal?.code} envoyees=$envoyees',
    );
    return notifications;
  }

  @override
  Future<void> creerNotification({
    required String titre,
    required String message,
    required CanalDeNotification canal,
    int? destinataireId,
  }) async {
    gestes.add('notifier:$titre:${canal.code}:$destinataireId');
  }

  @override
  Future<void> supprimerNotification(int id) async =>
      gestes.add('retirer-notification:$id');

  @override
  Future<List<PasserelleSmsItem>> fetchPasserelles() async => passerelles;

  @override
  Future<void> basculerPasserelle({required int id, required bool active}) async {
    gestes.add('basculer-passerelle:$id:$active');
  }

  @override
  Future<void> supprimerPasserelle(int id) async =>
      gestes.add('supprimer-passerelle:$id');

  @override
  Future<List<DestinataireItem>> fetchDestinataires() async => const [
    DestinataireItem(id: 40, libelle: 'Awa Traore — Parent'),
  ];
}

ModulePermissions _droits({
  AccessLevel communication = AccessLevel.admin,
  AccessLevel smsConfig = AccessLevel.none,
}) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'communication': ModulePermission(
        key: 'communication',
        label: 'Communication',
        group: 'administration',
        level: communication,
        scoped: false,
      ),
      'sms_config': ModulePermission(
        key: 'sms_config',
        label: 'Passerelle SMS',
        group: 'administration',
        level: smsConfig,
        scoped: false,
      ),
    },
  );
}

Future<void> _monter(
  WidgetTester tester,
  _FauxDepot depot, {
  AccessLevel communication = AccessLevel.admin,
  AccessLevel smsConfig = AccessLevel.none,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communicationRepositoryProvider.overrideWithValue(depot),
        currentPermissionsProvider.overrideWithValue(
          _droits(communication: communication, smsConfig: smsConfig),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: CommunicationModulePage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// On vise le `Tab`: « Notifications » nomme aussi un indicateur de l'en-tête.
Future<void> _ouvrir(WidgetTester tester, String onglet) async {
  await tester.tap(find.widgetWithText(Tab, onglet));
  await tester.pumpAndSettle();
}

/// Laisse l'avis de confirmation s'effacer de lui-même.
///
/// `ForegroundNotice` se retire au bout de trois secondes, et un minuteur
/// encore armé à la fin d'un test le fait échouer — quoi qu'aient dit les
/// assertions.
Future<void> _laisserPasserLAvis(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  group('La coque', () {
    testWidgets('les trois questions du module, dans cet ordre', (tester) async {
      await _monter(tester, _FauxDepot(), smsConfig: AccessLevel.admin);

      expect(find.widgetWithText(Tab, 'Annonces'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Notifications'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Passerelle SMS'), findsOneWidget);
    });

    testWidgets('ce qui attend encore de partir se lit sans changer d_onglet', (
      tester,
    ) async {
      // Le chiffre qu'on cherche quand une famille dit n'avoir rien reçu.
      await _monter(tester, _FauxDepot());

      expect(find.text('En attente d\'envoi'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('un profil en lecture seule le sait avant de cliquer', (
      tester,
    ) async {
      await _monter(tester, _FauxDepot(), communication: AccessLevel.read);

      expect(find.textContaining('Consultation seule'), findsOneWidget);
      expect(find.byKey(const Key('basculer-redaction-annonce')), findsNothing);
    });
  });

  group('Annonces', () {
    testWidgets('chaque annonce porte le public qui la lira', (tester) async {
      // Le défaut d'origine: l'écran n'affichait pas à qui il parlait.
      await _monter(tester, _FauxDepot());

      expect(find.text('Enseignants'), findsWidgets);
    });

    testWidgets('la rédaction reste pliée jusqu_à ce qu_on la demande', (
      tester,
    ) async {
      await _monter(tester, _FauxDepot());

      expect(find.byKey(const Key('annonce-titre')), findsNothing);

      await tester.tap(find.byKey(const Key('basculer-redaction-annonce')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('annonce-titre')), findsOneWidget);
    });

    testWidgets('le public se choisit, il ne se tape plus', (tester) async {
      final depot = _FauxDepot();
      await _monter(tester, depot);

      await tester.tap(find.byKey(const Key('basculer-redaction-annonce')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('annonce-titre')),
        'Réunion de parents',
      );
      await tester.enterText(
        find.byKey(const Key('annonce-message')),
        'Samedi à 9h.',
      );
      await tester.tap(find.byKey(const Key('annonce-public')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Familles (parents et élèves)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('publier-annonce')));
      await tester.pumpAndSettle();
      await _laisserPasserLAvis(tester);

      expect(depot.gestes, contains('publier:Réunion de parents:families'));
    });

    testWidgets('le filtre de public part au serveur', (tester) async {
      final depot = _FauxDepot();
      await _monter(tester, depot);

      await tester.tap(find.byKey(const Key('filtre-public')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enseignants').last);
      await tester.pumpAndSettle();

      expect(
        depot.filtres.any((filtre) => filtre.contains('public=teachers')),
        isTrue,
        reason: 'le filtre devait partir au serveur, non filtrer en mémoire',
      );
    });

    testWidgets('une annonce mal adressée se corrige sans être republiée', (
      tester,
    ) async {
      // Elle ne se corrigeait qu'en la supprimant et en la réécrivant, ce qui
      // la remontait en tête de liste comme une nouveauté.
      final depot = _FauxDepot();
      await _monter(tester, depot);

      await tester.tap(find.byKey(const ValueKey('changer-public-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Familles (parents et élèves)').last);
      await tester.pumpAndSettle();
      await _laisserPasserLAvis(tester);

      expect(depot.gestes, contains('corriger:3:families'));
    });

    testWidgets('le retrait dit qui perdra l_annonce', (tester) async {
      final depot = _FauxDepot();
      await _monter(tester, depot);

      await tester.tap(find.byKey(const ValueKey('retirer-annonce-3')));
      await tester.pumpAndSettle();
      await _laisserPasserLAvis(tester);

      expect(find.textContaining('enseignants'), findsWidgets);

      await tester.tap(find.byKey(const Key('confirmer-retrait-annonce')));
      await tester.pumpAndSettle();
      await _laisserPasserLAvis(tester);

      expect(depot.gestes, contains('retirer-annonce:3'));
    });
  });

  group('Notifications', () {
    testWidgets('ce qui attend passe avant ce qui est parti', (tester) async {
      await _monter(tester, _FauxDepot());
      await _ouvrir(tester, 'Notifications');

      final attente = tester.getTopLeft(
        find.text('En attente d\'envoi').last,
      );
      final parties = tester.getTopLeft(find.text('Parties'));

      expect(attente.dy, lessThan(parties.dy));
    });

    testWidgets('le destinataire vient du serveur, pas d_un cache local', (
      tester,
    ) async {
      // L'écran le résolvait sur l'annuaire qu'il gardait en mémoire et
      // affichait « Global » dès que la personne en était absente.
      await _monter(tester, _FauxDepot());
      await _ouvrir(tester, 'Notifications');

      expect(find.textContaining('Awa Traore'), findsWidgets);
    });

    testWidgets('« en attente » se demande au serveur', (tester) async {
      final depot = _FauxDepot();
      await _monter(tester, depot);
      await _ouvrir(tester, 'Notifications');

      await tester.tap(find.byKey(const Key('filtre-envoi')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('En attente').last);
      await tester.pumpAndSettle();

      expect(
        depot.filtres.any((filtre) => filtre.contains('envoyees=false')),
        isTrue,
      );
    });

    testWidgets('mettre en file ne se dit pas « envoyé »', (tester) async {
      // Rien ne part à cet instant: la tâche d'envoi s'en charge ensuite.
      final depot = _FauxDepot();
      await _monter(tester, depot);
      await _ouvrir(tester, 'Notifications');

      await tester.tap(
        find.byKey(const Key('basculer-redaction-notification')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mettre en file d\'envoi'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('notification-titre')),
        'Rappel de scolarité',
      );
      await tester.enterText(
        find.byKey(const Key('notification-message')),
        'Solde à régler.',
      );
      await tester.tap(find.byKey(const Key('creer-notification')));
      await tester.pumpAndSettle();
      await _laisserPasserLAvis(tester);

      expect(depot.gestes, contains('notifier:Rappel de scolarité:push:null'));
    });
  });

  group('Passerelle SMS', () {
    testWidgets('un canal se coupe sans perdre son jeton', (tester) async {
      // La suppression était la seule écriture proposée, et le jeton d'API
      // partait avec: il fallait le redemander au fournisseur pour rouvrir.
      final depot = _FauxDepot(
        passerelles: const [
          PasserelleSmsItem(
            id: 8,
            fournisseur: 'Orange Mali',
            urlApi: 'https://api.example.ml/sms',
            expediteur: 'ECOLE',
            active: true,
          ),
        ],
      );
      await _monter(tester, depot, smsConfig: AccessLevel.admin);
      await _ouvrir(tester, 'Passerelle SMS');

      await tester.tap(find.byKey(const ValueKey('basculer-passerelle-8')));
      await tester.pumpAndSettle();
      await _laisserPasserLAvis(tester);

      expect(depot.gestes, contains('basculer-passerelle:8:false'));
      expect(depot.gestes.where((geste) => geste.startsWith('supprimer')), isEmpty);
    });

    testWidgets('sans passerelle, l_écran dit que le canal est fermé', (
      tester,
    ) async {
      await _monter(tester, _FauxDepot(), smsConfig: AccessLevel.admin);
      await _ouvrir(tester, 'Passerelle SMS');

      expect(find.textContaining('canal SMS est fermé'), findsOneWidget);
    });

    testWidgets('la suppression prévient que le jeton sera perdu', (
      tester,
    ) async {
      final depot = _FauxDepot(
        passerelles: const [
          PasserelleSmsItem(
            id: 8,
            fournisseur: 'Orange Mali',
            urlApi: 'https://api.example.ml/sms',
            expediteur: 'ECOLE',
            active: true,
          ),
        ],
      );
      await _monter(tester, depot, smsConfig: AccessLevel.admin);
      await _ouvrir(tester, 'Passerelle SMS');

      await tester.tap(find.byKey(const ValueKey('supprimer-passerelle-8')));
      await tester.pumpAndSettle();

      expect(find.textContaining('jeton d\'API'), findsWidgets);

      await tester.tap(
        find.byKey(const Key('confirmer-suppression-passerelle')),
      );
      await tester.pumpAndSettle();
      await _laisserPasserLAvis(tester);

      expect(depot.gestes, contains('supprimer-passerelle:8'));
    });
  });
}
