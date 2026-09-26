/// Ce que le pilote de démonstration dit au montage.
///
/// Le pilote parcourt l'application pendant qu'un enregistreur filme l'écran.
/// Les deux ne se parlent pas : le montage, lui, doit savoir **à quelle
/// seconde** poser un carton de chapitre, un sous-titre ou un encadré, et
/// **où** dessiner cet encadré. Ce journal est ce canal, et il tient en une
/// ligne JSON par événement.
///
/// Il vit dans `lib/core/` et non dans le pilote lui-même pour une raison
/// pratique : `integration_test/` ne s'exécute qu'avec un appareil connecté,
/// alors que ce fichier-ci se teste comme n'importe quel autre. La logique qui
/// mérite un test n'est donc pas enfermée derrière un runner qu'on n'a pas
/// toujours sous la main.
///
/// Les rectangles viennent de `tester.getRect`, c'est-à-dire de ce que Flutter
/// a réellement calculé. Le montage n'a donc rien à deviner, et l'habillage
/// reste juste même si une mise en page change.
library;

import 'dart:convert';

/// La nature d'un événement du journal.
enum GenreDEvenement {
  /// Un changement de chapitre : le montage insère un carton de titre.
  chapitre,

  /// Une phrase à afficher en sous-titre, avec sa durée.
  sousTitre,

  /// Un rectangle à souligner à l'écran.
  cadre,

  /// La fin de la prise. Son absence signale une prise tronquée.
  fin,
}

/// Un rectangle de l'écran, tel que Flutter l'a mesuré.
class CadreDEcran {
  final double x;
  final double y;
  final double largeur;
  final double hauteur;

  const CadreDEcran({
    required this.x,
    required this.y,
    required this.largeur,
    required this.hauteur,
  });

  /// Décale le cadre du haut de la fenêtre vers le haut de la vidéo.
  ///
  /// La fenêtre GTK porte une barre de titre que la capture recadre : la vue
  /// Flutter ne commence donc pas à l'ordonnée zéro de l'image. Le décalage est
  /// mesuré à l'enregistrement, jamais supposé.
  CadreDEcran decaleDe(double decalageVertical) {
    return CadreDEcran(
      x: x,
      y: y + decalageVertical,
      largeur: largeur,
      hauteur: hauteur,
    );
  }

  List<double> get enListe => [x, y, largeur, hauteur];
}

/// Un événement daté, tel qu'il partira au montage.
class EvenementDeDemonstration {
  final GenreDEvenement genre;

  /// L'instant absolu. Le montage le ramène au temps de la vidéo en
  /// retranchant l'instant où la capture a commencé à écrire des images.
  final DateTime quand;

  final String texte;

  /// Le rôle dont le chapitre parle, pour les cartons de titre.
  final String role;

  /// Combien de temps tenir l'annotation à l'écran.
  final Duration duree;

  final CadreDEcran? cadre;

  const EvenementDeDemonstration({
    required this.genre,
    required this.quand,
    this.texte = '',
    this.role = '',
    this.duree = const Duration(seconds: 4),
    this.cadre,
  });

  Map<String, dynamic> enJson() => {
    'type': genre.name,
    'epoch_ms': quand.millisecondsSinceEpoch,
    if (texte.isNotEmpty) 'texte': texte,
    if (role.isNotEmpty) 'role': role,
    'duree_ms': duree.inMilliseconds,
    if (cadre != null) 'cadre': cadre!.enListe,
  };

  /// Relit un événement écrit par une prise précédente.
  ///
  /// Le montage en a besoin, et les tests aussi : écrire puis relire est la
  /// seule façon de prouver que le format tient.
  static EvenementDeDemonstration depuisJson(Map<String, dynamic> ligne) {
    final cadreBrut = ligne['cadre'];
    return EvenementDeDemonstration(
      genre: GenreDEvenement.values.firstWhere(
        (genre) => genre.name == ligne['type'],
        orElse: () => GenreDEvenement.sousTitre,
      ),
      quand: DateTime.fromMillisecondsSinceEpoch(
        (ligne['epoch_ms'] as num?)?.toInt() ?? 0,
      ),
      texte: ligne['texte']?.toString() ?? '',
      role: ligne['role']?.toString() ?? '',
      duree: Duration(
        milliseconds: (ligne['duree_ms'] as num?)?.toInt() ?? 4000,
      ),
      cadre: cadreBrut is List && cadreBrut.length == 4
          ? CadreDEcran(
              x: (cadreBrut[0] as num).toDouble(),
              y: (cadreBrut[1] as num).toDouble(),
              largeur: (cadreBrut[2] as num).toDouble(),
              hauteur: (cadreBrut[3] as num).toDouble(),
            )
          : null,
    );
  }
}

/// Le journal d'une prise, en mémoire puis sur disque.
///
/// Une ligne JSON par événement, et non un seul objet en fin de course : si une
/// prise s'interrompt au milieu, ce qui a été joué reste lisible et le montage
/// peut en tirer un chapitre partiel plutôt que rien.
class JournalDeDemonstration {
  final List<EvenementDeDemonstration> _evenements = [];

  /// L'horloge, injectable : un test ne peut pas attendre de vraies secondes.
  final DateTime Function() _maintenant;

  JournalDeDemonstration({DateTime Function()? horloge})
    : _maintenant = horloge ?? DateTime.now;

  List<EvenementDeDemonstration> get evenements =>
      List.unmodifiable(_evenements);

  void ouvrirLeChapitre(String role, String titre) {
    _evenements.add(
      EvenementDeDemonstration(
        genre: GenreDEvenement.chapitre,
        quand: _maintenant(),
        texte: titre,
        role: role,
        duree: const Duration(seconds: 3),
      ),
    );
  }

  void dire(String phrase, {Duration duree = const Duration(seconds: 4)}) {
    _evenements.add(
      EvenementDeDemonstration(
        genre: GenreDEvenement.sousTitre,
        quand: _maintenant(),
        texte: phrase,
        duree: duree,
      ),
    );
  }

  void souligner(
    CadreDEcran cadre, {
    String texte = '',
    Duration duree = const Duration(seconds: 4),
  }) {
    _evenements.add(
      EvenementDeDemonstration(
        genre: GenreDEvenement.cadre,
        quand: _maintenant(),
        texte: texte,
        duree: duree,
        cadre: cadre,
      ),
    );
  }

  void clore() {
    _evenements.add(
      EvenementDeDemonstration(
        genre: GenreDEvenement.fin,
        quand: _maintenant(),
        duree: Duration.zero,
      ),
    );
  }

  /// Le journal au format que le montage lit : une ligne JSON par événement.
  String enLignesJson() {
    return _evenements.map((e) => jsonEncode(e.enJson())).join('\n');
  }

  /// Relit un journal écrit par une prise.
  ///
  /// Les lignes vides et les lignes illisibles sont ignorées plutôt que de
  /// faire échouer la lecture : un fichier tronqué par une prise interrompue
  /// doit rendre ce qu'il contient.
  static List<EvenementDeDemonstration> relire(String contenu) {
    final evenements = <EvenementDeDemonstration>[];
    for (final ligne in contenu.split('\n')) {
      final propre = ligne.trim();
      if (propre.isEmpty) continue;
      try {
        final decode = jsonDecode(propre);
        if (decode is Map<String, dynamic>) {
          evenements.add(EvenementDeDemonstration.depuisJson(decode));
        }
      } on FormatException {
        continue;
      }
    }
    return evenements;
  }

  /// Vrai si la prise s'est terminée normalement.
  ///
  /// C'est ce que la chaîne de montage vérifie avant de garder un chapitre : un
  /// journal sans fin décrit une prise interrompue, et un chapitre tronqué vaut
  /// moins qu'un carton qui dit franchement qu'il manque.
  static bool priseComplete(List<EvenementDeDemonstration> evenements) {
    return evenements.isNotEmpty &&
        evenements.any((e) => e.genre == GenreDEvenement.chapitre) &&
        evenements.last.genre == GenreDEvenement.fin;
  }
}

/// Un chapitre de la démonstration.
class ChapitreDeDemonstration {
  final int rang;
  final String role;
  final String titre;
  final String mission;

  const ChapitreDeDemonstration({
    required this.rang,
    required this.role,
    required this.titre,
    required this.mission,
  });
}

/// Les neuf chapitres, dans l'ordre de la vidéo.
///
/// Déclarés ici et non dans chaque prise : le montage doit connaître l'ordre et
/// les titres sans avoir à exécuter les pilotes, et un test vérifie qu'aucun
/// rôle ne manque ni ne se répète.
const chapitresDeLaDemonstration = <ChapitreDeDemonstration>[
  ChapitreDeDemonstration(
    rang: 1,
    role: 'super_admin',
    titre: 'SUPER ADMIN',
    mission: 'Il installe l\'école et garde les clés.',
  ),
  ChapitreDeDemonstration(
    rang: 2,
    role: 'promoter',
    titre: 'PROMOTEUR',
    mission: 'Le propriétaire voit tout et ne touche à rien.',
  ),
  ChapitreDeDemonstration(
    rang: 3,
    role: 'director',
    titre: 'DIRECTEUR',
    mission: 'Il ouvre l\'année, compose les emplois du temps et publie.',
  ),
  ChapitreDeDemonstration(
    rang: 4,
    role: 'censor',
    titre: 'CENSEUR',
    mission: 'Il arbitre la pédagogie et vise la paie en premier.',
  ),
  ChapitreDeDemonstration(
    rang: 5,
    role: 'accountant',
    titre: 'COMPTABLE',
    mission: 'Il encaisse, justifie, et vise la paie en second.',
  ),
  ChapitreDeDemonstration(
    rang: 6,
    role: 'supervisor',
    titre: 'SURVEILLANT',
    mission: 'Il fait l\'appel, note la conduite et tient les épreuves.',
  ),
  ChapitreDeDemonstration(
    rang: 7,
    role: 'teacher',
    titre: 'ENSEIGNANT',
    mission: 'Il corrige et saisit — publier n\'est pas son geste.',
  ),
  ChapitreDeDemonstration(
    rang: 8,
    role: 'parent',
    titre: 'PARENT',
    mission: 'Il suit son enfant, et rien que son enfant.',
  ),
  ChapitreDeDemonstration(
    rang: 9,
    role: 'student',
    titre: 'ÉLÈVE',
    mission: 'Il lit ses notes, son emploi du temps et son fil de classe.',
  ),
];
