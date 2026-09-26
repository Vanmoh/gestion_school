/// Les gestes que les nueuf prises de démonstration partagent.
///
/// Ce n'est pas une suite de tests : c'est le pilote qui conduit l'application
/// pendant qu'un enregistreur filme l'écran. Il parle donc au vrai serveur —
/// `IntegrationTestWidgetsFlutterBinding` laisse passer les requêtes HTTP là où
/// `flutter_test` installe un client factice.
///
/// Trois règles de conception, qui ne sont pas des détails :
///
/// 1. **Jamais `pumpAndSettle`.** La politique d'images `fullyLive` laisse
///    tourner les animations, et un indicateur de chargement ne s'arrête
///    jamais : le settle attendrait l'expiration de la prise au lieu de
///    l'écran. Toute attente est donc bornée et dit ce qu'elle attendait.
/// 2. **La frappe se voit.** `enterText` pose la valeur d'un coup ; à l'image,
///    le champ se remplit par téléportation. Le pilote frappe caractère par
///    caractère.
/// 3. **Les rectangles viennent du vrai widget.** Avant de souligner quelque
///    chose, on journalise `tester.getRect` : le montage n'a rien à deviner, et
///    l'habillage reste juste même si la mise en page change.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/demonstration/journal_de_demonstration.dart';
import 'package:gestion_school_app/main.dart' as application;
import 'package:integration_test/integration_test.dart';

/// La durée que chaque écran reste à l'image.
///
/// Réglable par l'environnement plutôt que par `--dart-define` : celui-ci
/// forcerait une recompilation complète entre deux prises, alors que les neuf
/// partagent un seul build.
final Duration poseParEcran = Duration(
  milliseconds:
      int.tryParse(Platform.environment['DUREE_DE_POSE_MS'] ?? '') ?? 2500,
);

/// Le pilote d'une prise : l'application, le journal, et les gestes.
class PiloteDeDemonstration {
  final WidgetTester tester;
  final JournalDeDemonstration journal;

  PiloteDeDemonstration(this.tester) : journal = JournalDeDemonstration();

  /// Prépare le binding pour être filmé.
  ///
  /// `fullyLive` est la condition de toute la voie retenue : sans elle, le
  /// binding ne peint que les images explicitement demandées, et la capture
  /// enregistre une image figée entre deux gestes.
  static IntegrationTestWidgetsFlutterBinding preparerLeBinding() {
    final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    return binding;
  }

  /// Lance l'application et attend que quelque chose soit monté.
  Future<void> demarrer() async {
    application.main();
    await _pomperUnPeu(const Duration(seconds: 2));
  }

  // ------------------------------------------------------------- les attentes

  Future<void> _pomperUnPeu(Duration duree) async {
    // Par petits pas: un seul `pump` d'une longue durée saute les images
    // intermédiaires, et c'est précisément elles qu'on filme.
    const pas = Duration(milliseconds: 60);
    var ecoule = Duration.zero;
    while (ecoule < duree) {
      await tester.pump(pas);
      ecoule += pas;
    }
  }

  /// Attend qu'un widget paraisse, puis le laisse à l'image.
  ///
  /// Rend `false` plutôt que d'échouer : une prise doit pouvoir continuer sans
  /// l'écran qu'elle espérait, et le journal dira ce qui manquait. Une prise
  /// qui s'arrête au troisième écran ne donne rien ; une prise incomplète
  /// donne un chapitre.
  Future<bool> attendre(
    Finder cible, {
    Duration limite = const Duration(seconds: 20),
    bool poser = true,
  }) async {
    final echeance = DateTime.now().add(limite);
    while (DateTime.now().isBefore(echeance)) {
      if (cible.evaluate().isNotEmpty) {
        if (poser) await _pomperUnPeu(poseParEcran);
        return true;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    journal.dire('(écran introuvable : ${cible.describeMatch(Plurality.one)})');
    return false;
  }

  Future<bool> attendreLaCle(String cle, {Duration? limite}) {
    return attendre(
      find.byKey(Key(cle)),
      limite: limite ?? const Duration(seconds: 20),
    );
  }

  Future<bool> attendreLeTexte(String texte, {Duration? limite}) {
    return attendre(
      find.textContaining(texte),
      limite: limite ?? const Duration(seconds: 20),
    );
  }

  /// Laisse l'écran en place, sans rien attendre.
  Future<void> poser({Duration? duree}) => _pomperUnPeu(duree ?? poseParEcran);

  // -------------------------------------------------------------- les gestes

  /// Appuie sur un widget, et laisse le réticule du binding se voir.
  ///
  /// Le binding peint un cercle et une croix à chaque appui : c'est
  /// l'indicateur de clic de la vidéo, et il ne coûte rien.
  Future<bool> appuyer(Finder cible, {Duration? apres}) async {
    if (cible.evaluate().isEmpty) {
      journal.dire('(bouton absent : ${cible.describeMatch(Plurality.one)})');
      return false;
    }
    await tester.ensureVisible(cible.first);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(cible.first, warnIfMissed: false);
    await _pomperUnPeu(apres ?? const Duration(milliseconds: 900));
    return true;
  }

  Future<bool> appuyerSurLaCle(String cle, {Duration? apres}) {
    return appuyer(find.byKey(Key(cle)), apres: apres);
  }

  /// Frappe un texte caractère par caractère, pour que la saisie se voie.
  Future<void> taperLentement(Finder champ, String texte) async {
    if (champ.evaluate().isEmpty) {
      journal.dire('(champ absent : ${champ.describeMatch(Plurality.one)})');
      return;
    }
    await tester.tap(champ.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));

    final tampon = StringBuffer();
    for (final lettre in texte.split('')) {
      tampon.write(lettre);
      tester.testTextInput.enterText(tampon.toString());
      await tester.pump(const Duration(milliseconds: 45));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Fait défiler doucement, pour montrer le bas d'un écran.
  Future<void> defiler(Finder liste, double distance) async {
    if (liste.evaluate().isEmpty) return;
    const pas = 60.0;
    var parcouru = 0.0;
    while (parcouru.abs() < distance.abs()) {
      final increment = distance.isNegative ? -pas : pas;
      await tester.drag(liste.first, Offset(0, -increment));
      await tester.pump(const Duration(milliseconds: 90));
      parcouru += increment;
    }
    await _pomperUnPeu(const Duration(milliseconds: 600));
  }

  // ------------------------------------------------------ la vie du logiciel

  /// Franchit le portail public s'il est là, puis se connecte.
  ///
  /// Le portail n'apparaît pas toujours : le choix d'établissement peut être
  /// retenu d'une prise à l'autre quand le trousseau du système fonctionne. Le
  /// pilote regarde donc quel écran est monté au lieu de supposer l'un des deux.
  Future<void> seConnecter(String identifiant, String motDePasse) async {
    await attendre(find.byType(TextField), poser: false);

    // Le portail liste les établissements: on prend la première tuile.
    final tuiles = find.byType(Card);
    if (find.textContaining('Choisir').evaluate().isNotEmpty &&
        tuiles.evaluate().isNotEmpty) {
      await appuyer(tuiles.first);
    }

    final champs = find.byType(TextField);
    if (champs.evaluate().length < 2) {
      journal.dire('(écran de connexion introuvable)');
      return;
    }

    await taperLentement(champs.at(0), identifiant);
    await taperLentement(champs.at(1), motDePasse);

    final bouton = find.byType(FilledButton);
    if (bouton.evaluate().isNotEmpty) {
      await appuyer(bouton.first, apres: const Duration(seconds: 3));
    }
    await _pomperUnPeu(const Duration(seconds: 2));
  }

  /// Ouvre un module par sa clé de menu.
  ///
  /// Par la clé et jamais par le libellé : celui-ci change selon le rôle, si
  /// bien qu'un pilote qui viserait le texte ouvrirait autre chose d'un profil
  /// à l'autre.
  Future<bool> ouvrirLeModule(String cleDuModule, {String? sousTitre}) async {
    final entree = find.byKey(ValueKey('menu-$cleDuModule'));
    if (entree.evaluate().isEmpty) {
      journal.dire('(module fermé à ce profil : $cleDuModule)');
      return false;
    }
    await appuyer(entree, apres: const Duration(milliseconds: 1200));
    if (sousTitre != null) journal.dire(sousTitre);
    await _pomperUnPeu(poseParEcran);
    return true;
  }

  /// Souligne un widget à l'image, en journalisant son vrai rectangle.
  Future<void> souligner(
    Finder cible, {
    String texte = '',
    Duration? duree,
  }) async {
    if (cible.evaluate().isEmpty) return;
    final rect = tester.getRect(cible.first);
    journal.souligner(
      CadreDEcran(
        x: rect.left,
        y: rect.top,
        largeur: rect.width,
        hauteur: rect.height,
      ),
      texte: texte,
      duree: duree ?? const Duration(seconds: 4),
    );
    await _pomperUnPeu(duree ?? const Duration(seconds: 3));
  }

  Future<void> soulignerLaCle(String cle, {String texte = ''}) {
    return souligner(find.byKey(Key(cle)), texte: texte);
  }

  /// Ouvre un onglet par son libellé, en visant le `Tab` et non le texte.
  ///
  /// Plusieurs écrans nomment un indicateur comme leur onglet — « Notifications »
  /// est à la fois un onglet et un compteur d'en-tête.
  Future<bool> ouvrirLOnglet(String libelle) async {
    return appuyer(
      find.widgetWithText(Tab, libelle),
      apres: const Duration(milliseconds: 1200),
    );
  }

  // ------------------------------------------------------------- la clôture

  /// Referme la prise et écrit son journal.
  ///
  /// Le chemin vient de l'environnement. Sans lui, le journal part sur la
  /// sortie d'erreur : une prise lancée à la main doit rester lisible.
  Future<void> clore() async {
    journal.clore();
    final chemin = Platform.environment['JOURNAL_DEMO'];
    final contenu = journal.enLignesJson();
    if (chemin == null || chemin.isEmpty) {
      stderr.writeln(contenu);
      return;
    }
    final fichier = File(chemin);
    await fichier.parent.create(recursive: true);
    await fichier.writeAsString('$contenu\n');
  }
}

/// Le squelette d'une prise, commun aux neuf rôles.
///
/// Chaque prise ouvre son chapitre, se connecte, joue ses gestes et écrit son
/// journal — même si l'un des gestes a échoué. C'est ce qui permet au montage
/// de garder un chapitre partiel plutôt que de perdre la prise entière.
Future<void> jouerLaPrise({
  required WidgetTester tester,
  required String role,
  required String identifiant,
  required String motDePasse,
  required Future<void> Function(PiloteDeDemonstration pilote) gestes,
}) async {
  final pilote = PiloteDeDemonstration(tester);
  final chapitre = chapitresDeLaDemonstration.firstWhere(
    (c) => c.role == role,
  );

  pilote.journal.ouvrirLeChapitre(role, chapitre.titre);
  pilote.journal.dire(chapitre.mission);

  await pilote.demarrer();
  await pilote.seConnecter(identifiant, motDePasse);

  try {
    await gestes(pilote);
  } finally {
    await pilote.clore();
  }
}
