import 'package:flutter/material.dart';

/// Ce qu'il faut savoir d'un enseignant pour agir sur lui.
///
/// Meme grammaire que la palette eleve: en-tete identifiant, trois blocs de
/// champs, puis des indicateurs. La remuneration en est volontairement
/// absente -- salaire de base et taux horaire restent dans le module Paie,
/// ou l'acces est deja restreint. Cet ecran-ci sert a savoir qui enseigne
/// quoi, pas ce qu'il coute.
class TeacherPaletteCard extends StatelessWidget {
  /// Compte utilisateur: nom, email, telephone.
  final Map<String, dynamic> user;

  /// Profil enseignant: code employe, date d'embauche. Absent tant que le
  /// profil n'a pas ete cree pour ce compte.
  final Map<String, dynamic>? profile;

  final List<Map<String, dynamic>> assignments;
  final List<Map<String, dynamic>> scheduleSlots;
  final List<Map<String, dynamic>> timeEntries;

  final bool loading;
  final List<Widget> actions;
  final VoidCallback? onClear;

  const TeacherPaletteCard({
    super.key,
    required this.user,
    required this.profile,
    this.assignments = const [],
    this.scheduleSlots = const [],
    this.timeEntries = const [],
    this.loading = false,
    this.actions = const [],
    this.onClear,
  });

  static const nonRenseigne = 'Non renseigné';
  static const sansProfil = 'Profil enseignant non créé';

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
                        ('Nom et prénom', _nomComplet()),
                        ('Identifiant', _texte(user['username'])),
                      ]),
                    ),
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Poste', [
                        ('Code employé', _texte(profile?['employee_code'])),
                        ('Embauche', _date(profile?['hire_date'])),
                        ('Ancienneté', _anciennete()),
                      ]),
                    ),
                    SizedBox(
                      width: largeur,
                      child: _bloc(scheme, textTheme, 'Contacts', [
                        ('Email', _texte(user['email'])),
                        ('Téléphone', _texte(user['phone'])),
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
          url: (user['profile_photo'] ?? '').toString(),
          initiales: _initiales(_nomComplet()),
          scheme: scheme,
          textTheme: textTheme,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _nomComplet(),
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
                  if (profile != null)
                    _pastille(
                      scheme,
                      textTheme,
                      _texte(profile?['employee_code']),
                    )
                  else
                    // Un compte sans profil ne peut recevoir ni affectation
                    // ni emargement: le dire ici evite de chercher pourquoi
                    // les indicateurs restent vides.
                    _pastille(
                      scheme,
                      textTheme,
                      sansProfil,
                      couleur: scheme.errorContainer,
                      texteCouleur: scheme.onErrorContainer,
                    ),
                  if (_texte(user['etablissement_name']).isNotEmpty)
                    _pastille(
                      scheme,
                      textTheme,
                      _texte(user['etablissement_name']),
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
    final matieres = <String>{};
    final classes = <String>{};
    for (final ligne in assignments) {
      final matiere = _texte(ligne['subject_name']);
      final classe = _texte(ligne['classroom_name']);
      if (matiere.isNotEmpty) matieres.add(matiere);
      if (classe.isNotEmpty) classes.add(classe);
    }

    final minutes = _minutesHebdomadaires();
    final retards = timeEntries
        .where((row) => _entier(row['late_minutes']) > 0)
        .length;

    if (assignments.isEmpty && scheduleSlots.isEmpty && timeEntries.isEmpty) {
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
              Icons.info_outline,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                profile == null
                    ? 'Créez le profil enseignant pour lui affecter des '
                          'matières et suivre son émargement.'
                    : 'Aucune affectation, aucun créneau, aucun émargement.',
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
          icone: Icons.menu_book_outlined,
          titre: 'Affectations',
          valeur: matieres.isEmpty
              ? 'Aucune'
              : '${matieres.length} matière${matieres.length > 1 ? 's' : ''}',
          detail: classes.isEmpty
              ? null
              : '${classes.length} classe${classes.length > 1 ? 's' : ''}',
          alerte: assignments.isEmpty,
        ),
        _indicateur(
          scheme,
          textTheme,
          icone: Icons.calendar_month_outlined,
          titre: 'Emploi du temps',
          valeur: scheduleSlots.isEmpty
              ? 'Aucun créneau'
              : '${scheduleSlots.length} créneau${scheduleSlots.length > 1 ? 'x' : ''}',
          detail: minutes == 0 ? null : '${_heures(minutes)} par semaine',
          alerte: scheduleSlots.isEmpty,
        ),
        _indicateur(
          scheme,
          textTheme,
          icone: Icons.how_to_reg_outlined,
          titre: 'Émargement',
          valeur: timeEntries.isEmpty
              ? 'Aucun pointage'
              : '${timeEntries.length} pointage${timeEntries.length > 1 ? 's' : ''}',
          detail: retards == 0
              ? null
              : '$retards retard${retards > 1 ? 's' : ''}',
          alerte: retards > 0,
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
          Icon(icone, size: 20, color: alerte ? scheme.error : scheme.primary),
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

  String _nomComplet() {
    final complet = _texte(user['full_name']);
    if (complet.isNotEmpty) return complet;

    final parties = [
      _texte(user['first_name']),
      _texte(user['last_name']),
    ].where((mot) => mot.isNotEmpty);
    if (parties.isNotEmpty) return parties.join(' ');

    return _texte(user['username']);
  }

  /// Duree hebdomadaire, calculee sur les creneaux et non saisie a part: deux
  /// sources pour un meme total finissent par diverger.
  int _minutesHebdomadaires() {
    var total = 0;
    for (final creneau in scheduleSlots) {
      final debut = _minutes(creneau['start_time']);
      final fin = _minutes(creneau['end_time']);
      if (debut != null && fin != null && fin > debut) {
        total += fin - debut;
      }
    }
    return total;
  }

  String _anciennete() {
    final embauche = _dateTime(profile?['hire_date']);
    if (embauche == null) return '';

    final maintenant = DateTime.now();
    var annees = maintenant.year - embauche.year;
    final avantAnniversaire =
        maintenant.month < embauche.month ||
        (maintenant.month == embauche.month && maintenant.day < embauche.day);
    if (avantAnniversaire) annees -= 1;

    if (annees < 0) return '';
    if (annees == 0) return "Moins d'un an";
    return '$annees an${annees > 1 ? 's' : ''}';
  }

  static String _heures(int minutes) {
    final heures = minutes ~/ 60;
    final reste = minutes % 60;
    if (heures == 0) return '$reste min';
    if (reste == 0) return '${heures}h';
    return '${heures}h$reste';
  }

  static int? _minutes(dynamic valeur) {
    final texte = _texte(valeur);
    if (texte.isEmpty) return null;
    final morceaux = texte.split(':');
    if (morceaux.length < 2) return null;
    final heures = int.tryParse(morceaux[0]);
    final minutes = int.tryParse(morceaux[1]);
    if (heures == null || minutes == null) return null;
    return heures * 60 + minutes;
  }

  static String _texte(dynamic valeur) => (valeur ?? '').toString().trim();

  static int _entier(dynamic valeur) {
    if (valeur is int) return valeur;
    return int.tryParse(_texte(valeur)) ?? 0;
  }

  static DateTime? _dateTime(dynamic valeur) {
    final texte = _texte(valeur);
    return texte.isEmpty ? null : DateTime.tryParse(texte);
  }

  static String _date(dynamic valeur) {
    final date = _dateTime(valeur);
    if (date == null) return '';
    final jour = date.day.toString().padLeft(2, '0');
    final mois = date.month.toString().padLeft(2, '0');
    return '$jour/$mois/${date.year}';
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
}

/// Photo de l'enseignant, ou son emplacement quand elle manque.
///
/// L'annuaire ne fournit l'adresse qu'aux profils autorises: sans elle, et
/// sur un lien mort, on retombe sur les initiales -- jamais sur l'icone
/// d'image cassee du navigateur, qui se lit comme un defaut de l'application.
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
    final repli = Center(
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
