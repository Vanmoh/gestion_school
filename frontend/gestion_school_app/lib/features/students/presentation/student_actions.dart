import 'package:flutter/material.dart';

/// Une action d'ecriture proposee sur un eleve, et son etat.
///
/// Sortie de la page pour etre verifiable: tant que la regle vivait dans une
/// methode privee d'un State de 5 000 lignes, un test ne pouvait que la
/// reecrire -- et un test qui reecrit la regle qu'il verifie ne verifie rien.
@immutable
class StudentAction {
  final String label;
  final IconData icon;
  final bool enabled;
  final String tooltip;

  const StudentAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.tooltip,
  });
}

const String lectureSeuleMotif =
    'Votre profil consulte les élèves sans les modifier.';

/// Actions de la palette, dans l'ordre d'affichage.
///
/// Toutes ecrivent, et la page les protege deja au moment d'enregistrer. Mais
/// cette garde-la n'intervenait qu'apres le clic: on ouvrait le formulaire, on
/// le remplissait, puis on apprenait « Mode lecture seule ». Grisees, elles
/// disent non avant l'effort -- et le motif accompagne le grisage, sans quoi
/// un bouton eteint passe pour une panne.
List<StudentAction> buildStudentActions({
  required bool canWrite,
  required bool saving,
  required String studentName,
  bool archive = false,
  bool peutDispenser = false,
  bool dispenseEnCours = false,
}) {
  final definitions = <(String, IconData)>[
    ('Éditer', Icons.edit_outlined),
    ('Historique', Icons.history_edu_outlined),
    ('Incident', Icons.gavel_outlined),
    ('Absence', Icons.fact_check_outlined),
    ('Frais', Icons.add_card_outlined),
    ('Paiement', Icons.payments_outlined),
    // Remontees ici depuis le panneau du dossier complet, supprime avec la
    // vue par classe: elles portent sur l'eleve affiche, donc elles vivent
    // dans sa palette. Sans ce deplacement, archiver un eleve n'aurait plus
    // eu aucun chemin.
    (archive ? 'Réactiver' : 'Archiver',
     archive ? Icons.unarchive_outlined : Icons.archive_outlined),
    if (peutDispenser)
      (dispenseEnCours ? 'Lever la dispense' : 'Dispenser d\'inscription',
       Icons.volunteer_activism_outlined),
  ];

  final actif = canWrite && !saving;

  return [
    for (final (label, icon) in definitions)
      StudentAction(
        label: label,
        icon: icon,
        enabled: actif,
        tooltip: canWrite
            ? (studentName.isEmpty ? label : '$label — $studentName')
            : lectureSeuleMotif,
      ),
  ];
}
