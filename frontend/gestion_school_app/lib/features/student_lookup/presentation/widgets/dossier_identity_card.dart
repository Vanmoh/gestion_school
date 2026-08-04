import 'package:flutter/material.dart';

import '../../../students/domain/student.dart';

/// Bloc « INFORMATIONS ÉLÈVE » : la fiche d'identite, en un coup d'oeil.
///
/// Un champ vide affiche « Non renseigné » plutot qu'un blanc: un blanc se lit
/// comme un defaut d'affichage, alors que c'est une donnee manquante a saisir.
class DossierIdentityCard extends StatelessWidget {
  final Student student;

  /// Injectee pour que l'age affiche soit testable sans dependre du jour.
  final DateTime? today;

  const DossierIdentityCard({super.key, required this.student, this.today});

  static const nonRenseigne = 'Non renseigné';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final age = student.ageAt(today ?? DateTime.now());

    final champs = <({String label, String value})>[
      (label: 'Nom et prénom', value: student.fullName),
      (label: 'Matricule', value: student.matricule),
      (label: 'Classe', value: student.classroomName),
      (label: 'Genre', value: _genre(student.gender)),
      (label: 'Date de naissance', value: _date(student.birthDate)),
      (label: 'Âge', value: age == null ? '' : '$age ans'),
      (label: 'Parent / tuteur', value: student.parentName),
      (label: 'Téléphone parent', value: student.parentPhone),
      (label: 'Téléphone élève', value: student.phone),
      (label: 'Email', value: student.email),
      (label: "Date d'inscription", value: _date(student.enrollmentDate)),
      (label: 'Identifiant', value: student.username),
    ];

    return _Panel(
      title: 'INFORMATIONS ÉLÈVE',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Trois colonnes comme le portail de reference, deux puis une quand
          // la largeur ne suit plus.
          final colonnes = constraints.maxWidth > 620
              ? 3
              : (constraints.maxWidth > 380 ? 2 : 1);
          final largeur =
              (constraints.maxWidth - (colonnes - 1) * 16) / colonnes;

          return Wrap(
            spacing: 16,
            runSpacing: 18,
            children: [
              for (final champ in champs)
                SizedBox(
                  width: largeur,
                  child: _Field(
                    label: champ.label,
                    value: champ.value,
                    scheme: scheme,
                    textTheme: textTheme,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _genre(String code) {
    switch (code) {
      case 'M':
        return 'Masculin';
      case 'F':
        return 'Féminin';
      default:
        return '';
    }
  }

  static String _date(DateTime? value) {
    if (value == null) return '';
    final jour = value.day.toString().padLeft(2, '0');
    final mois = value.month.toString().padLeft(2, '0');
    return '$jour/$mois/${value.year}';
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme scheme;
  final TextTheme textTheme;

  const _Field({
    required this.label,
    required this.value,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final renseigne = value.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 8),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: renseigne
                  ? scheme.primary
                  : scheme.outlineVariant,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                renseigne ? value : DossierIdentityCard.nonRenseigne,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: renseigne ? FontWeight.w600 : FontWeight.w400,
                  color: renseigne
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  fontStyle: renseigne ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Encadre commun aux deux colonnes du dossier.
class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// Reutilise par le panneau des sections, pour que les deux colonnes du
/// dossier partagent exactement le meme encadre.
class DossierPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const DossierPanel({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => _Panel(title: title, child: child);
}
