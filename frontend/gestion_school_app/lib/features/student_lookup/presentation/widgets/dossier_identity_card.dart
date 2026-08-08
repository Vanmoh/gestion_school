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

  /// Adresse absolue de la photo, deja resolue par l'appelant qui seul
  /// connait l'URL de base de l'API.
  final String photoUrl;

  const DossierIdentityCard({
    super.key,
    required this.student,
    this.today,
    this.photoUrl = '',
  });

  static const nonRenseigne = 'Non renseigné';
  static const photoAbsente = 'Photo non fournie';

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
          final photo = _Photo(
            url: photoUrl,
            initiales: _initiales(student.fullName),
          );
          // La photo prend sa colonne tant qu'il reste de quoi lire les champs
          // a cote; en dessous elle passe au-dessus d'eux.
          final photoACote = constraints.maxWidth > 520;
          final largeurChamps = photoACote
              ? constraints.maxWidth - _Photo.taille - 18
              : constraints.maxWidth;

          final colonnes = largeurChamps > 560
              ? 3
              : (largeurChamps > 330 ? 2 : 1);
          final largeur = (largeurChamps - (colonnes - 1) * 16) / colonnes;

          final grille = Wrap(
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

          if (!photoACote) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [photo, const SizedBox(height: 18), grille],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              photo,
              const SizedBox(width: 18),
              Expanded(child: grille),
            ],
          );
        },
      ),
    );
  }

  /// Initiales de repli, pour que l'emplacement reste identifiable quand
  /// aucune photo n'a ete televersee.
  static String _initiales(String nomComplet) {
    final mots = nomComplet
        .trim()
        .split(RegExp(r'\s+'))
        .where((mot) => mot.isNotEmpty)
        .toList();
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first.characters.first.toUpperCase();
    return (mots.first.characters.first + mots.last.characters.first)
        .toUpperCase();
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

/// Photo de l'eleve, ou son emplacement quand elle manque.
///
/// Le chargement peut echouer pour de bon -- lien signe expire, stockage
/// injoignable. On retombe alors sur les initiales plutot que sur l'icone
/// d'image cassee du navigateur, qui se lit comme un bug de l'application.
class _Photo extends StatelessWidget {
  final String url;
  final String initiales;

  static const taille = 132.0;

  const _Photo({required this.url, required this.initiales});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: taille,
          height: taille,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: url.isEmpty
              ? _Initiales(initiales: initiales, scheme: scheme)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _Initiales(initiales: initiales, scheme: scheme),
                ),
        ),
        if (url.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              width: taille,
              child: Text(
                DossierIdentityCard.photoAbsente,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Initiales extends StatelessWidget {
  final String initiales;
  final ColorScheme scheme;

  const _Initiales({required this.initiales, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initiales,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
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
