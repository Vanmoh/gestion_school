class DashboardStats {
  final int students;
  final double monthlyRevenue;
  final double monthlyExpenses;

  /// Depenses saisies mais pas encore validees jusqu'au second niveau.
  ///
  /// Elles n'entrent pas dans le benefice -- elles l'amputaient avant, sans
  /// que rien ne le dise -- mais l'ecran doit les montrer: une ecole qui n'a
  /// pas encore fait tourner son circuit de validation doit voir ou sont
  /// passees ses depenses.
  final double monthlyExpensesPending;
  final double monthlyProfit;
  final int monthlyAbsences;

  /// Les heures réellement manquées, quand l'école les compte.
  ///
  /// Toutes ne quantifient pas: le nombre d'absences reste la mesure
  /// principale, et ce champ vaut alors zéro. Un lycée qui compte les heures
  /// veut ce chiffre-là plutôt qu'un nombre de journées qui mélange une
  /// matinée et une semaine.
  final double monthlyAbsenceHours;

  final int classrooms;
  final int teachers;
  final int? activeEtablissementId;
  final String? activeEtablissementName;
  final String? activeEtablissementAddress;
  final String? activeEtablissementPhone;
  final String? activeEtablissementEmail;

  /// L'année que ces chiffres décrivent.
  ///
  /// Le tableau de bord ne la nommait pas, et ne la consultait pas non plus:
  /// sur une école ayant deux années ouvertes il annonçait 611 élèves pour
  /// 450 inscrits et 30 classes pour 15. Un écran qui nomme son année rend ce
  /// genre d'écart visible au premier regard.
  final String? academicYearName;
  final String? academicYearStart;
  final String? academicYearEnd;
  final bool academicYearClosed;

  /// Le recouvrement: facturé, rentré, restant.
  ///
  /// C'est le chiffre d'une école malienne, et il manquait entièrement. À sa
  /// place, un « Bénéfice net » qui était en réalité le montant encaissé, les
  /// charges non doublement validées étant exclues du calcul.
  final double feesDue;
  final double feesCollected;
  final double feesOutstanding;
  final double collectionRate;

  /// L'école, en face de l'argent.
  ///
  /// Le tableau de bord ne parlait que de caisse — recettes, dépenses,
  /// bénéfice. Sur l'écran d'accueil d'un directeur d'école, aucun signal
  /// pédagogique: ni moyenne, ni bulletin, ni présence des enseignants.
  /// 26 730 notes saisies sur IFP-OBK, et pas un mot à l'accueil.
  final double generalAverage;
  final int gradesCount;
  final int bulletinsDelivered;
  final int bulletinsTotal;
  final int bulletinsFailed;

  /// L'assiduité des enseignants, que l'écran passait sous silence alors
  /// qu'il montrait celle des élèves. On paie à l'heure.
  final int teacherAbsences;
  final int teacherLate;

  /// La masse salariale: la principale charge de l'école.
  final double payrollTotal;
  final int payrollCount;

  final int stockBelowThreshold;
  final int stockTotal;

  /// Des nombres qui appellent une action, et non un décompte.
  final int studentsUnpaid;
  final int studentsUnassigned;
  final double yearExpensesPending;
  final int yearExpensesPendingCount;

  const DashboardStats({
    required this.students,
    required this.monthlyRevenue,
    required this.monthlyExpenses,
    this.monthlyExpensesPending = 0,
    required this.monthlyProfit,
    required this.monthlyAbsences,
    this.monthlyAbsenceHours = 0,
    required this.classrooms,
    required this.teachers,
    this.activeEtablissementId,
    this.activeEtablissementName,
    this.activeEtablissementAddress,
    this.activeEtablissementPhone,
    this.activeEtablissementEmail,
    this.academicYearName,
    this.academicYearStart,
    this.academicYearEnd,
    this.academicYearClosed = false,
    this.feesDue = 0,
    this.feesCollected = 0,
    this.feesOutstanding = 0,
    this.collectionRate = 0,
    this.studentsUnpaid = 0,
    this.studentsUnassigned = 0,
    this.yearExpensesPending = 0,
    this.yearExpensesPendingCount = 0,
    this.generalAverage = 0,
    this.gradesCount = 0,
    this.bulletinsDelivered = 0,
    this.bulletinsTotal = 0,
    this.bulletinsFailed = 0,
    this.teacherAbsences = 0,
    this.teacherLate = 0,
    this.payrollTotal = 0,
    this.payrollCount = 0,
    this.stockBelowThreshold = 0,
    this.stockTotal = 0,
  });

  /// La part des bulletins effectivement remis, pour la jauge.
  ///
  /// `null` quand aucun bulletin n'est attendu: une jauge à zéro laisserait
  /// croire à un retard là où il n'y a simplement rien à remettre.
  double? get partDesBulletins {
    if (bulletinsTotal == 0) return null;
    return bulletinsDelivered / bulletinsTotal;
  }

  /// La phrase qui accompagne l'assiduité des enseignants.
  String get phraseDesEnseignants {
    if (teacherAbsences == 0 && teacherLate == 0) {
      return 'aucune absence ni retard relevés';
    }
    final morceaux = <String>[];
    if (teacherAbsences > 0) {
      morceaux.add(
        '$teacherAbsences ${teacherAbsences == 1 ? "absence" : "absences"}',
      );
    }
    if (teacherLate > 0) {
      morceaux.add('$teacherLate ${teacherLate == 1 ? "retard" : "retards"}');
    }
    return '${morceaux.join(" et ")} côté enseignants';
  }

  /// La phrase qui accompagne le nombre d'absences.
  ///
  /// Les heures quand l'école les compte, la provenance du chiffre sinon. Un
  /// nombre nu laisse chacun deviner s'il s'agit de journées, d'heures ou
  /// d'élèves.
  String get phraseDesAbsences {
    if (monthlyAbsenceHours > 0) {
      final heures = monthlyAbsenceHours == monthlyAbsenceHours.roundToDouble()
          ? monthlyAbsenceHours.round().toString()
          : monthlyAbsenceHours.toStringAsFixed(1).replaceAll('.', ',');
      return 'soit $heures heures de cours manquées';
    }
    return 'relevées à l\'appel ce mois-ci';
  }
}

/// Une échéance du barème, et ce qui est rentré dessus.
class MoisDEcheance {
  final String libelle;
  final double du;
  final double encaisse;
  final double manque;

  const MoisDEcheance({
    required this.libelle,
    required this.du,
    required this.encaisse,
    required this.manque,
  });
}

/// L'échéancier de l'année contre les encaissements.
///
/// La courbe précédente s'appuyait sur `created_at` des paiements, c'est-à-dire
/// l'heure de saisie: `Payment` ne porte aucune date de paiement. Un reçu
/// écrit le 30 et saisi le 2 tombait dans le mois suivant, et un import en
/// masse faisait tenir une année entière dans un seul mois.
///
/// Ici le mois vient de l'échéance, fixée par le barème. La série décrit donc
/// l'école et non le rythme de saisie du caissier.
class Echeancier {
  final String academicYearName;
  final List<MoisDEcheance> mois;
  final double du;
  final double encaisse;

  const Echeancier({
    required this.academicYearName,
    required this.mois,
    required this.du,
    required this.encaisse,
  });

  double get manque => du - encaisse;

  /// Le premier mois où l'encaissement décroche, s'il y en a un.
  ///
  /// C'est la phrase que la direction veut lire — « depuis avril » — plutôt
  /// qu'un total qu'elle devra situer elle-même.
  MoisDEcheance? get premierDecrochage {
    for (final ligne in mois) {
      if (ligne.manque > 0) {
        return ligne;
      }
    }
    return null;
  }
}

/// Un mois de l'année scolaire, tel que la caisse l'a vécu.
class MoisFinancier {
  final String mois;
  final String libelle;
  final double recettes;
  final double depenses;
  final double benefice;

  const MoisFinancier({
    required this.mois,
    required this.libelle,
    required this.recettes,
    required this.depenses,
    required this.benefice,
  });
}

/// Le rapport financier de l'année, mois par mois.
///
/// L'écran d'accueil traçait jusqu'ici une courbe fabriquée: trois points
/// obtenus en multipliant le montant du mois courant par des coefficients
/// écrits en dur, étiquetés « S-3, S-2, S-1 ». La direction lisait une
/// tendance qui n'existait pas.
class FinancesAnnuelles {
  final String academicYearName;
  final List<MoisFinancier> mois;
  final double totalRecettes;
  final double totalDepenses;
  final double benefice;

  const FinancesAnnuelles({
    this.academicYearName = '',
    this.mois = const [],
    this.totalRecettes = 0,
    this.totalDepenses = 0,
    this.benefice = 0,
  });

  bool get estVide => mois.isEmpty;
}


/// Qui est en ligne maintenant, par rôle.
///
/// « En ligne » n'est pas une approximation ici: le projet tient une
/// WebSocket ouverte (Channels + Redis), le client bat toutes les vingt
/// secondes, et chaque appel REST rafraîchit aussi la présence. La règle vient
/// de `apps/common/presence.py` — **un signe de vie dans les 75 secondes**,
/// trois battements manqués — et elle ignore délibérément le compteur de
/// connexions, qui reste bloqué quand un socket meurt sans prévenir.
///
/// Sa propre route, non mise en cache: la charge utile du tableau de bord est
/// gardée soixante secondes, et y glisser la présence l'aurait figée.
class PresenceParRole {
  /// La fenêtre que le serveur applique, en secondes. Affichée telle quelle
  /// plutôt que recopiée: deux définitions de « en ligne » finiraient par se
  /// contredire.
  final int fenetreSecondes;
  final int totalEnLigne;
  final Map<String, int> enLigneParRole;
  final Map<String, int> jamaisConnectesParRole;
  final Map<String, int> comptesParRole;

  const PresenceParRole({
    this.fenetreSecondes = 75,
    this.totalEnLigne = 0,
    this.enLigneParRole = const {},
    this.jamaisConnectesParRole = const {},
    this.comptesParRole = const {},
  });

  /// Le rôle dont le plus de comptes n'ont jamais ouvert l'application.
  ///
  /// C'est la question la plus urgente sur une base réelle: 74 enseignants sur
  /// 75 n'ont jamais ouvert l'application, et aucun écran ne le disait.
  (String, int)? get leRoleLePlusAbsent {
    String? pire;
    var combien = 0;
    jamaisConnectesParRole.forEach((role, n) {
      if (n > combien) {
        pire = role;
        combien = n;
      }
    });
    return pire == null ? null : (pire!, combien);
  }
}
