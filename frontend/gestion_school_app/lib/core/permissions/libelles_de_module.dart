/// Le nom d'un module, dit du point de vue de celui qui l'ouvre.
///
/// Un module porte le nom que lui donne l'administration: « Gestion des
/// élèves », « Émargements », « Finances ». C'est le bon nom pour qui pilote
/// l'établissement, et le mauvais pour tous les autres: l'écran « Gestion des
/// élèves » ne montre à un enseignant que ses propres classes, « Émargements »
/// ne montre à un parent que les absences de ses enfants, et « Finances » ne
/// montre à un enseignant que sa fiche de paie. Chacun lisait pourtant la même
/// étiquette, et y cherchait ce qu'elle promet.
///
/// La restriction elle-même n'est pas ici: elle est appliquée par le backend,
/// et la matrice la note d'une étoile. Ce fichier ne fait que la traduire en
/// français. Y ajouter une entrée ne donne ni ne retire aucun droit.
library;

/// Module -> role -> libellé propre à ce profil.
///
/// L'absence d'entrée est le cas normal: le nom du module convient alors tel
/// quel. On ne renomme que là où l'étiquette administrative ferait chercher
/// autre chose que ce que l'écran contient.
const Map<String, Map<String, String>> libellesDeModuleParRole = {
  // L'enseignant n'y trouve que les classes où il intervient.
  'students': {'teacher': 'Mes élèves'},

  // C'est par cette entrée que la famille atteint le dossier: l'écran complet
  // lui reste fermé, faute du référentiel scolaire qu'il charge d'abord.
  'student_lookup': {'student': 'Mon dossier', 'parent': 'Mes enfants'},

  'attendance': {
    'student': 'Mes absences',
    'parent': 'Absences de mes enfants',
    // Le comptable n'a pas l'appel des élèves: il n'entre ici que par
    // l'émargement des enseignants, qu'il paie.
    'accountant': 'Émargement enseignants',
  },

  'discipline': {
    'student': 'Ma discipline',
    'parent': 'Discipline de mes enfants',
  },

  'grades': {
    'student': 'Mes notes & bulletins',
    'parent': 'Notes de mes enfants',
    'teacher': 'Notes de mes classes',
  },

  'exams': {'student': 'Mes examens', 'parent': 'Examens de mes enfants'},

  'timetable': {
    'student': 'Mon emploi du temps',
    'parent': 'Emploi du temps de mes enfants',
    'teacher': 'Mon emploi du temps',
  },

  'finance': {
    'student': 'Mes frais scolaires',
    'parent': 'Frais de mes enfants',
    // Ces deux-là n'ont pas les finances courantes: ils n'entrent dans cet
    // écran que par la paie, chacun de son côté de la double validation.
    'teacher': 'Ma paie',
    'censor': 'Paie enseignants',
  },

  'reports': {
    'student': 'Mes documents',
    'parent': 'Documents de mes enfants',
    'teacher': 'Rapports de mes classes',
  },
};

/// Le libellé à afficher, ou [parDefaut] si ce profil n'en a pas de propre.
String libelleDeModule(
  String module,
  String role, {
  required String parDefaut,
}) {
  return libellesDeModuleParRole[module]?[role] ?? parDefaut;
}
