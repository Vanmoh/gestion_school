import 'package:flutter/material.dart';

import '../../domain/student.dart';

/// Photo de l'eleve, ou son emplacement quand elle manque.
///
/// Un lien signe expire ou un stockage injoignable retombent sur les
/// initiales, jamais sur l'icone d'image cassee du navigateur, qui se lit
/// comme un defaut de l'application.
class _Photo extends StatelessWidget {
  final String url;
  final String initiales;
  final ColorScheme scheme;
  final TextTheme textTheme;

  /// Assez grande pour reconnaitre un visage a cote d'un nom en gros
  /// caracteres: a 56 elle passait pour une puce decorative.
  static const taille = 76.0;

  const _Photo({
    required this.url,
    required this.initiales,
    required this.scheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final repli = StudentPaletteCard._initialesWidget(
      initiales,
      scheme,
      textTheme,
    );

    return Container(
      width: taille,
      height: taille,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: url.isEmpty
          ? repli
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => repli,
            ),
    );
  }
}

/// Ce qu'il faut savoir d'un eleve pour agir sur lui.
///
/// Deliberement plus courte que le dossier consolide de « Recherche eleve »:
/// cette page-ci sert a modifier. On y montre l'identite, la scolarite, le
/// parent, l'etat des frais et ce qui s'est passe recemment -- pas les onze
/// rubriques, qui noieraient les boutons d'action.
class StudentPaletteCard extends StatelessWidget {
  final Student student;
  final List<Map<String, dynamic>> fees;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> attendances;
  final List<Map<String, dynamic>> incidents;
  final List<Map<String, dynamic>> history;
  final bool loading;

  /// Adresse absolue de la photo, deja resolue par l'appelant.
  final String photoUrl;

  /// Boutons d'ecriture, places sous le nom: on agit la ou on regarde.
  final List<Widget> actions;

  /// Presente seulement quand la recherche avait plusieurs reponses: sinon le
  /// bouton proposerait de revenir a une liste qui n'existe pas.
  final VoidCallback? onClear;

  const StudentPaletteCard({
    super.key,
    required this.student,
    required this.fees,
    required this.payments,
    required this.attendances,
    required this.incidents,
    required this.history,
    this.loading = false,
    this.photoUrl = '',
    this.actions = const [],
    this.onClear,
  });

  static const nonRenseigne = 'Non renseigné';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(scheme, textTheme),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final colonnes = constraints.maxWidth > 900
                    ? 3
                    : (constraints.maxWidth > 560 ? 2 : 1);
                final largeur =
                    (constraints.maxWidth - (colonnes - 1) * 16) / colonnes;

                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Identité', [
                        ('Nom et prénom', student.fullName),
                        ('Matricule', student.matricule),
                        ('Genre', _genre(student.gender)),
                        ('Date de naissance', _date(student.birthDate)),
                        ('Âge', _age(student)),
                      ]),
                    ),
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Scolarité', [
                        ('Classe', student.classroomName),
                        ('Inscription', _date(student.enrollmentDate)),
                        ('Statut', student.isArchived ? 'Archivé' : 'Actif'),
                        ('Identifiant', student.username),
                      ]),
                    ),
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Contacts', [
                        ('Parent / tuteur', student.parentName),
                        ('Téléphone parent', student.parentPhone),
                        ('Téléphone élève', student.phone),
                        ('Email', student.email),
                      ]),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _buildIndicateurs(scheme, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, TextTheme textTheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Photo(
          url: photoUrl,
          initiales: _initiales(student.fullName),
          scheme: scheme,
          textTheme: textTheme,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student.fullName,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _pastille(scheme, textTheme, student.matricule),
                  if (student.classroomName.trim().isNotEmpty)
                    _pastille(scheme, textTheme, student.classroomName),
                  if (student.isArchived)
                    _pastille(
                      scheme,
                      textTheme,
                      'Archivé',
                      couleur: scheme.errorContainer,
                      texteCouleur: scheme.onErrorContainer,
                    ),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          ),
        ),
        if (onClear != null)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Résultats'),
          ),
      ],
    );
  }

  Widget _buildIndicateurs(ColorScheme scheme, TextTheme textTheme) {
    var du = 0.0;
    var paye = 0.0;
    for (final ligne in fees) {
      du += _nombre(ligne['amount_due']);
      paye += _nombre(ligne['amount_paid']);
    }
    final reste = du - paye;

    final absences = attendances
        .where((row) => row['is_absent'] == true)
        .length;
    final retards = attendances.where((row) => row['is_late'] == true).length;
    final ouverts = incidents
        .where((row) => (row['status'] ?? '').toString() != 'resolved')
        .length;

    // Quatre tuiles pour dire quatre fois « rien » occupent une rangee sans
    // rien apprendre. Une phrase suffit; les tuiles reviennent des qu'il y a
    // quelque chose a montrer.
    if (fees.isEmpty &&
        attendances.isEmpty &&
        incidents.isEmpty &&
        history.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Rien à signaler : aucun frais, aucune absence, '
                'aucun incident, aucun historique.',
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _indicateur(
          scheme,
          textTheme,
          icone: Icons.account_balance_wallet_outlined,
          titre: 'Frais',
          valeur: du == 0
              ? 'Aucun frais'
              : '${_money(reste)} restant',
          detail: du == 0 ? null : '${_money(du)} dû · ${_money(paye)} payé',
          alerte: reste > 0,
        ),
        _indicateur(
          scheme,
          textTheme,
          icone: Icons.event_busy_outlined,
          titre: 'Assiduité',
          valeur: absences == 0 && retards == 0
              ? 'Rien à signaler'
              : '$absences absence${absences > 1 ? 's' : ''}',
          detail: retards == 0
              ? null
              : '$retards retard${retards > 1 ? 's' : ''}',
          alerte: absences > 0,
        ),
        _indicateur(
          scheme,
          textTheme,
          icone: Icons.gavel_outlined,
          titre: 'Discipline',
          valeur: incidents.isEmpty
              ? 'Aucun incident'
              : '${incidents.length} incident${incidents.length > 1 ? 's' : ''}',
          detail: ouverts == 0 ? null : '$ouverts ouvert${ouverts > 1 ? 's' : ''}',
          alerte: ouverts > 0,
        ),
        _indicateur(
          scheme,
          textTheme,
          icone: Icons.history_edu_outlined,
          titre: 'Historique',
          valeur: history.isEmpty
              ? 'Aucune année'
              : '${history.length} année${history.length > 1 ? 's' : ''}',
          detail: payments.isEmpty
              ? null
              : '${payments.length} paiement${payments.length > 1 ? 's' : ''}',
        ),
      ],
    );
  }

  Widget _indicateur(
    ColorScheme scheme,
    TextTheme textTheme, {
    required IconData icone,
    required String titre,
    required String valeur,
    String? detail,
    bool alerte = false,
  }) {
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: alerte
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icone,
            size: 20,
            color: alerte ? scheme.error : scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre.toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  valeur,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloc(
    ColorScheme scheme,
    TextTheme textTheme,
    String titre,
    List<(String, String)> champs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titre.toUpperCase(),
          style: textTheme.labelSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        for (final (label, valeur) in champs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                // Un blanc se lit comme un defaut d'affichage; le motif ecrit
                // dit que la donnee reste a saisir.
                Text(
                  valeur.trim().isEmpty ? nonRenseigne : valeur,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: valeur.trim().isEmpty
                        ? FontWeight.w400
                        : FontWeight.w600,
                    fontStyle: valeur.trim().isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                    color: valeur.trim().isEmpty
                        ? scheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pastille(
    ColorScheme scheme,
    TextTheme textTheme,
    String texte, {
    Color? couleur,
    Color? texteCouleur,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: texteCouleur ?? scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static Widget _initialesWidget(
    String initiales,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Center(
      child: Text(
        initiales,
        // Suit la taille du cercle: en titleMedium les initiales flottaient
        // au milieu d'un disque devenu plus grand.
        style: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }

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

  static String _genre(String code) => switch (code.toUpperCase()) {
    'M' => 'Masculin',
    'F' => 'Féminin',
    _ => '',
  };

  static String _date(DateTime? value) {
    if (value == null) return '';
    final jour = value.day.toString().padLeft(2, '0');
    final mois = value.month.toString().padLeft(2, '0');
    return '$jour/$mois/${value.year}';
  }

  static String _age(Student student) {
    final age = student.ageAt(DateTime.now());
    return age == null ? '' : '$age ans';
  }

  static double _nombre(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _money(double value) {
    final entier = value.round().abs().toString();
    final buffer = StringBuffer();
    for (var index = 0; index < entier.length; index++) {
      if (index > 0 && (entier.length - index) % 3 == 0) buffer.write(' ');
      buffer.write(entier[index]);
    }
    return '${value < 0 ? '-' : ''}$buffer F';
  }
}
