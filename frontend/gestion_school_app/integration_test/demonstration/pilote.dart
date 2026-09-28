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
import 'package:gestion_school_app/features/auth/presentation/widgets/login_form_card.dart';
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
  ///
  /// **Par le contrôleur du champ, et par rien d'autre.** Ni
  /// `testTextInput.enterText`, ni `tester.enterText` qui s'appuie dessus, ne
  /// fonctionnent ici : `IntegrationTestWidgetsFlutterBinding` déclare
  /// `registerTestTextInput => false`, donc le clavier de test n'est jamais
  /// enregistré. Quatre tournages s'y sont arrêtés, et en silence — le
  /// formulaire restait vide, le bouton n'envoyait rien, et le serveur n'a
  /// jamais vu passer la moindre demande d'authentification. Le journal parlait
  /// pendant ce temps de modules « fermés à ce profil ».
  ///
  /// Écrire dans le contrôleur met le champ à jour et déclenche la validation
  /// du formulaire, qui lit cette même valeur. On repose la valeur lettre après
  /// lettre: la frappe se voit à l'image, sans dépendre d'un clavier absent.
  Future<void> taperLentement(Finder champ, String texte) async {
    final controleur = _controleurDe(champ);
    if (controleur == null) {
      journal.dire('(champ absent : ${champ.describeMatch(Plurality.one)})');
      return;
    }

    await tester.tap(champ.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 250));

    for (var longueur = 1; longueur <= texte.length; longueur++) {
      final morceau = texte.substring(0, longueur);
      controleur.value = TextEditingValue(
        text: morceau,
        selection: TextSelection.collapsed(offset: morceau.length),
      );
      await tester.pump(const Duration(milliseconds: 45));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Le contrôleur de texte d'un champ, ou `null` s'il n'y en a pas.
  TextEditingController? _controleurDe(Finder champ) {
    if (champ.evaluate().isEmpty) return null;
    final editable = find.descendant(
      of: champ,
      matching: find.byType(EditableText),
    );
    if (editable.evaluate().isEmpty) return null;
    return tester.widget<EditableText>(editable.first).controller;
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

  /// Les tuiles d'établissement du portail.
  ///
  /// Elles portent `tile-<id>`; « Demander un accès » en porte une aussi,
  /// `tile-request-access`, qu'il faut écarter — la viser ouvrirait un
  /// formulaire de demande au lieu d'entrer dans l'école.
  Finder _tuilesDEtablissement() {
    return find.byWidgetPredicate(_estUneTuileDEtablissement);
  }

  /// Filtre le portail sur un nom d'établissement, par sa barre de recherche.
  ///
  /// Par la recherche et non en remontant l'arbre des widgets: les tuiles sont
  /// posées dans une grille animée, et retrouver celle qui porte un nom donné
  /// dépendait de la structure interne de cette grille. Chercher est en plus ce
  /// qu'un utilisateur fait, donc ce qu'il est juste de filmer.
  Future<void> _chercherLEtablissement(String nom) async {
    final recherche = find.byType(TextField);
    if (recherche.evaluate().isEmpty) return;
    await taperLentement(recherche.first, nom);
    await _pomperUnPeu(const Duration(milliseconds: 900));
  }

  static bool _estUneTuileDEtablissement(Widget widget) {
    final cle = widget.key;
    if (cle is! ValueKey<String>) return false;
    return cle.value.startsWith('tile-') && cle.value != 'tile-request-access';
  }

  /// La carte « Reprendre », quand une école a déjà été ouverte ici.
  ///
  /// Le portail sort alors cet établissement de la grille et le met à part:
  /// chercher une tuile à son nom ne rendrait rien, alors qu'il est bien là.
  /// Le script d'enregistrement donne un dossier personnel neuf à chaque prise,
  /// mais une prise relancée à la main tombe sur ce cas.
  Finder _carteDeReprise() {
    return find.byWidgetPredicate((widget) {
      final cle = widget.key;
      return cle is ValueKey<String> && cle.value.startsWith('resume-');
    });
  }

  /// Franchit le portail public, puis se connecte.
  ///
  /// Le premier tournage s'est arrêté ici, et tous les chapitres en ont pâti:
  /// le pilote comptait les `TextField` pour reconnaître l'écran de connexion,
  /// or l'application démarre sur le **portail** — qui n'en a qu'un, sa barre de
  /// recherche. Le compte n'arrivait donc jamais à deux, la connexion était
  /// abandonnée, et chaque module semblait « fermé à ce profil » puisque
  /// personne n'était connecté. Neuf prises de trois minutes sur un écran de
  /// choix d'établissement.
  ///
  /// On vise donc des clés: la tuile de l'établissement, puis les deux champs
  /// que `login_form_card.dart` expose.
  Future<void> seConnecter(
    String identifiant,
    String motDePasse, {
    String? etablissement,
  }) async {
    // Le portail peut ne pas paraître: le choix se retient d'une prise à
    // l'autre quand le trousseau du système fonctionne.
    final tuiles = _tuilesDEtablissement();
    if (await attendre(tuiles, limite: const Duration(seconds: 25),
        poser: false)) {
      journal.dire('On entre par le portail de l\'établissement.');

      if (etablissement != null && etablissement.trim().isNotEmpty) {
        await _chercherLEtablissement(etablissement.trim());
      }

      // Une recherche qui ne laisse rien ne doit pas laisser le pilote sur le
      // portail: on efface et on reprend la liste entière. Entrer dans une
      // autre école vaut mieux que ne pas entrer du tout — et le journal le
      // dira, ce qu'un abandon silencieux ne faisait pas.
      var restantes = _tuilesDEtablissement();
      if (restantes.evaluate().isEmpty &&
          _carteDeReprise().evaluate().isEmpty) {
        journal.dire('(la recherche n\'a laissé aucune école : on l\'efface)');
        final champ = find.byType(TextField);
        if (champ.evaluate().isNotEmpty) {
          await tester.enterText(champ.first, '');
          await _pomperUnPeu(const Duration(milliseconds: 900));
        }
        restantes = _tuilesDEtablissement();
      }

      if (restantes.evaluate().isNotEmpty) {
        journal.dire('École choisie : ${_nomDeLaTuile(restantes.first)}.');
        await appuyer(restantes.first, apres: const Duration(seconds: 3));
      } else if (_carteDeReprise().evaluate().isNotEmpty) {
        // L'école cherchée est celle qu'on a déjà ouverte: elle n'est plus
        // dans la grille, elle est en tête sous « Reprendre ».
        await appuyer(
          _carteDeReprise().first,
          apres: const Duration(seconds: 3),
        );
        journal.dire('École reprise.');
      } else {
        journal.dire('(aucune école à choisir sur le portail)');
      }
    } else {
      journal.dire('(pas de portail : le choix était déjà fait)');
    }

    if (!await attendre(
      find.byKey(kChampIdentifiant),
      limite: const Duration(seconds: 25),
      poser: false,
    )) {
      journal.dire('(écran de connexion introuvable)');
      return;
    }

    await taperLentement(find.byKey(kChampIdentifiant), identifiant);
    await taperLentement(find.byKey(kChampMotDePasse), motDePasse);

    // On relit ce qui est réellement dans le champ. Deux tournages se sont
    // arrêtés sur un formulaire vide sans que rien ne le dise: le serveur n'a
    // jamais vu passer de demande d'authentification, et le journal parlait
    // pourtant de modules « fermés à ce profil ».
    journal.dire('Identifiant saisi : « ${_contenuDuChamp(kChampIdentifiant)} ».');

    final bouton = find.widgetWithText(FilledButton, 'Se connecter');
    if (bouton.evaluate().isNotEmpty) {
      await appuyer(bouton.first, apres: const Duration(seconds: 5));
      journal.dire('Connexion demandée.');
    } else {
      // Repli: le libellé change pendant la connexion, la forme reste.
      final secours = find.byType(FilledButton);
      if (secours.evaluate().isNotEmpty) {
        await appuyer(secours.last, apres: const Duration(seconds: 5));
        journal.dire('Connexion demandée (bouton de repli).');
      } else {
        journal.dire('(aucun bouton de connexion trouvé)');
      }
    }

    // On attend la barre latérale, preuve que la session est ouverte: sans
    // elle, la prise filmerait un écran de connexion en boucle.
    final entree = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('menu-'),
    );
    if (!await attendre(entree, limite: const Duration(seconds: 30))) {
      journal.dire('(la session ne s\'est pas ouverte)');
    }
  }

  /// Ce qu'un champ contient réellement, pour le dire au journal.
  ///
  /// Un mot de passe n'y passe jamais: le journal part en artefact public.
  String _contenuDuChamp(Key cle) {
    return _controleurDe(find.byKey(cle))?.text ?? '(champ absent)';
  }

  /// Ouvre un module par sa clé de menu.
  ///
  /// Par la clé et jamais par le libellé : celui-ci change selon le rôle, si
  /// bien qu'un pilote qui viserait le texte ouvrirait autre chose d'un profil
  /// à l'autre.
  Future<bool> ouvrirLeModule(String cleDuModule, {String? sousTitre}) async {
    final entree = find.byKey(ValueKey('menu-$cleDuModule'));

    // La barre latérale défile, et ce qui est hors écran n'est pas construit:
    // un super-administrateur, qui a pourtant tous les droits, se voyait
    // refuser cinq modules parce que leurs entrées étaient simplement plus bas
    // que la fenêtre. Un écran absent de l'arbre n'est pas un écran fermé.
    if (entree.evaluate().isEmpty) {
      await _amenerLEntreeDansLaVue(entree);
    }

    if (entree.evaluate().isEmpty) {
      journal.dire('(module fermé à ce profil : $cleDuModule)');
      return false;
    }
    await appuyer(entree, apres: const Duration(milliseconds: 1200));
    if (sousTitre != null) journal.dire(sousTitre);
    await _pomperUnPeu(poseParEcran);
    return true;
  }

  /// Le nom porté par une tuile d'établissement, pour le dire au journal.
  ///
  /// Entrer dans la mauvaise école déconnecte aussitôt — le serveur a
  /// enregistré la séquence: connexion acceptée, puis `logout` dans la seconde.
  /// Savoir laquelle a été choisie est donc la première chose à journaliser.
  String _nomDeLaTuile(Finder tuile) {
    final textes = find.descendant(of: tuile, matching: find.byType(Text));
    for (final element in textes.evaluate()) {
      final texte = (element.widget as Text).data ?? '';
      if (texte.trim().length > 3) return texte.trim();
    }
    return '(nom illisible)';
  }

  /// Fait défiler la barre latérale jusqu'à une entrée de menu.
  ///
  /// On remonte d'abord au `Scrollable` qui porte les entrées — celui de la
  /// barre, et non celui de la page ouverte à côté, qui défilerait sans jamais
  /// révéler le menu.
  Future<void> _amenerLEntreeDansLaVue(Finder entree) async {
    final repere = find.byKey(const ValueKey('menu-dashboard'));
    final connue = repere.evaluate().isNotEmpty
        ? repere
        : find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key as ValueKey<String>).value.startsWith('menu-'),
          );
    if (connue.evaluate().isEmpty) return;

    final barre = find.ancestor(of: connue.first, matching: find.byType(Scrollable));
    if (barre.evaluate().isEmpty) return;

    try {
      await tester.scrollUntilVisible(
        entree,
        140,
        scrollable: barre.first,
        maxScrolls: 30,
      );
      await tester.pump(const Duration(milliseconds: 300));
    } catch (_) {
      // L'entrée n'existe pas pour ce profil: c'est un module réellement
      // fermé, et l'appelant le dira.
    }
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

  /// Tous les modules de l'application, dans l'ordre de la barre latérale.
  ///
  /// Les six derniers noms de `_items` sont des groupes, pas des écrans: ils
  /// n'ont pas d'entrée de menu à ouvrir.
  static const modulesDeLApplication = <String>[
    'dashboard',
    'students',
    'student_lookup',
    'teachers',
    'academics',
    'academic_imports',
    'grades',
    'promotion',
    'attendance',
    'discipline',
    'exams',
    'timetable',
    'finance',
    'reports',
    'activity_logs',
    'backup_restore',
    'users',
    'etablissements',
    'personnalisation',
    'communication',
    'library',
    'canteen',
    'stock',
  ];

  /// Ouvre chaque écran ouvert à ce profil, l'un après l'autre.
  ///
  /// Le propos d'un tel passage n'est pas de montrer un geste mais **l'étendue
  /// du profil**: ce qu'un rôle voit, et ce qu'il ne voit pas. Les modules
  /// fermés sont sautés sans bruit — `ouvrirLeModule` ne trouve pas leur entrée
  /// de menu, ce qui est la définition même d'un module fermé.
  ///
  /// Il vient **après** les gestes distinctifs de chaque chapitre: on montre
  /// d'abord le métier, puis l'inventaire.
  Future<int> parcourirTousLesModules({
    Duration pose = const Duration(milliseconds: 2200),
    Set<String> sauter = const {},
  }) async {
    var ouverts = 0;
    for (final cle in modulesDeLApplication) {
      if (sauter.contains(cle)) continue;
      final entree = find.byKey(ValueKey('menu-$cle'));
      if (entree.evaluate().isEmpty) {
        await _amenerLEntreeDansLaVue(entree);
      }
      if (entree.evaluate().isEmpty) continue;
      await appuyer(entree, apres: const Duration(milliseconds: 900));
      await poser(duree: pose);
      ouverts++;
    }
    journal.dire('$ouverts écrans ouverts à ce profil.');
    return ouverts;
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
  String? etablissement,
}) async {
  final pilote = PiloteDeDemonstration(tester);
  final chapitre = chapitresDeLaDemonstration.firstWhere(
    (c) => c.role == role,
  );

  pilote.journal.ouvrirLeChapitre(role, chapitre.titre);
  pilote.journal.dire(chapitre.mission);

  await pilote.demarrer();
  await pilote.seConnecter(
    identifiant,
    motDePasse,
    // `Platform.environment` et non `String.fromEnvironment`: la seconde lit
    // les `--dart-define`, qui sont figes a la compilation -- changer d'ecole
    // aurait impose de recompiler entre deux prises.
    etablissement:
        etablissement ?? Platform.environment['ETABLISSEMENT_DEMO'] ?? '',
  );

  try {
    await gestes(pilote);
  } finally {
    await pilote.clore();
  }
}
