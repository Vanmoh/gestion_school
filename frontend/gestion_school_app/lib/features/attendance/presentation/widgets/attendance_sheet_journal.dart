import 'package:flutter/material.dart';

/// Les fiches d'appel deja enregistrees, une ligne par classe et par date.
///
/// Une fois la fiche enregistree, rien ne permettait de la revoir: il fallait
/// resaisir sa classe et sa date de memoire. L'historique qui occupait cette
/// place listait les enregistrements un par un, tous eleves et toutes dates
/// melanges -- illisible des la premiere semaine.
class AttendanceSheetJournal extends StatelessWidget {
  final List<Map<String, dynamic>> fiches;
  final bool loading;

  /// Ouvre la fiche en lecture, telle qu'elle sera imprimee.
  final void Function(int classroomId, String date) onVoir;

  /// Ramene la fiche dans la feuille d'appel, pour la corriger.
  ///
  /// C'etait autrefois le seul geste offert, sous l'etiquette « Voir »: on
  /// croyait consulter et on rouvrait la saisie -- sans rien voir, la feuille
  /// etant hors de l'ecran.
  final void Function(int classroomId, String date) onModifier;
  final void Function(int classroomId, String date) onExporterPdf;
  final void Function(int classroomId, String date) onExporterExcel;

  const AttendanceSheetJournal({
    super.key,
    required this.fiches,
    required this.loading,
    required this.onVoir,
    required this.onModifier,
    required this.onExporterPdf,
    required this.onExporterExcel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (fiches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Aucune fiche enregistrée sur cette période.',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return Column(
          children: [
            if (!compact) _EnTete(textTheme: textTheme),
            for (final fiche in fiches)
              _LigneFiche(
                fiche: fiche,
                compact: compact,
                onVoir: onVoir,
                onModifier: onModifier,
                onExporterPdf: onExporterPdf,
                onExporterExcel: onExporterExcel,
              ),
          ],
        );
      },
    );
  }
}

class _EnTete extends StatelessWidget {
  final TextTheme textTheme;

  const _EnTete({required this.textTheme});

  @override
  Widget build(BuildContext context) {
    final style = textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        children: [
          SizedBox(width: 92, child: Text('DATE', style: style)),
          Expanded(child: Text('CLASSE', style: style)),
          SizedBox(width: 66, child: Text('EFFECTIF', style: style)),
          SizedBox(width: 62, child: Text('ABSENTS', style: style)),
          SizedBox(width: 62, child: Text('RETARDS', style: style)),
          SizedBox(width: 96, child: Text('ÉTAT', style: style)),
          SizedBox(width: 176, child: Text('', style: style)),
        ],
      ),
    );
  }
}

class _LigneFiche extends StatelessWidget {
  final Map<String, dynamic> fiche;
  final bool compact;
  final void Function(int, String) onVoir;
  final void Function(int, String) onModifier;
  final void Function(int, String) onExporterPdf;
  final void Function(int, String) onExporterExcel;

  const _LigneFiche({
    required this.fiche,
    required this.compact,
    required this.onVoir,
    required this.onModifier,
    required this.onExporterPdf,
    required this.onExporterExcel,
  });

  int get _classroomId => _entier(fiche['classroom']);
  String get _date => (fiche['date'] ?? '').toString();
  bool get _verrouillee => fiche['is_locked'] == true;
  int get _absents => _entier(fiche['absents']);

  static int _entier(dynamic valeur) {
    if (valeur is int) return valeur;
    return int.tryParse(valeur?.toString() ?? '') ?? 0;
  }

  static String _dateLisible(String brut) {
    final date = DateTime.tryParse(brut);
    if (date == null) return brut;
    final jour = date.day.toString().padLeft(2, '0');
    final mois = date.month.toString().padLeft(2, '0');
    return '$jour/$mois/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 10 : 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: compact
          ? _buildCompact(context, scheme, textTheme)
          : _buildLarge(context, scheme, textTheme),
    );
  }

  Widget _buildLarge(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Row(
      children: [
        SizedBox(width: 92, child: Text(_dateLisible(_date))),
        Expanded(
          child: Text(
            (fiche['classroom_name'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(width: 66, child: Text('${fiche['effectif'] ?? 0}')),
        SizedBox(width: 62, child: _compteAbsents(scheme)),
        SizedBox(width: 62, child: Text('${fiche['retards'] ?? 0}')),
        SizedBox(width: 96, child: _etat(scheme, textTheme)),
        SizedBox(width: 176, child: _actions(scheme)),
      ],
    );
  }

  Widget _buildCompact(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_dateLisible(_date)}  ·  ${fiche['classroom_name'] ?? ''}',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Borne indispensable: une Row donne a ses enfants sans flex une
            // largeur illimitee. `_etat` contient un Flexible, et un Flexible
            // sous contrainte illimitee fait echouer RenderFlex. En large le
            // SizedBox(width: 96) fournissait cette borne; ici, rien ne la
            // fournissait.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: _etat(scheme, textTheme),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                '${fiche['effectif'] ?? 0} élèves  ·  '
                '${fiche['absents'] ?? 0} absents  ·  '
                '${fiche['retards'] ?? 0} retards',
                style: textTheme.bodySmall?.copyWith(
                  color: _absents > 0 ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ),
            _actions(scheme),
          ],
        ),
      ],
    );
  }

  Widget _compteAbsents(ColorScheme scheme) {
    return Text(
      '$_absents',
      style: TextStyle(
        // Une fiche sans absent n'appelle pas l'attention; une fiche qui en
        // compte, si.
        color: _absents > 0 ? scheme.error : null,
        fontWeight: _absents > 0 ? FontWeight.w700 : null,
      ),
    );
  }

  Widget _etat(ColorScheme scheme, TextTheme textTheme) {
    // Une fiche non validee reste modifiable: le dire evite de croire que
    // l'appel du jour est clos.
    final libelle = _verrouillee ? 'Validée' : 'Brouillon';
    final validePar = (fiche['validated_by_name'] ?? '').toString();

    return Tooltip(
      message: _verrouillee && validePar.isNotEmpty
          ? 'Validée par $validePar'
          : libelle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _verrouillee ? Icons.lock_outline : Icons.edit_note_outlined,
            size: 15,
            color: _verrouillee ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Voir la fiche',
          visualDensity: VisualDensity.compact,
          onPressed: () => onVoir(_classroomId, _date),
          icon: const Icon(Icons.visibility_outlined, size: 19),
        ),
        IconButton(
          // Une fiche validee se charge aussi, mais en lecture seule: la
          // reprendre sans pouvoir l'ecrire reste utile pour verifier un nom.
          tooltip: _verrouillee
              ? 'Ouvrir dans la feuille (validée, lecture seule)'
              : 'Modifier dans la feuille d\'appel',
          visualDensity: VisualDensity.compact,
          onPressed: () => onModifier(_classroomId, _date),
          // Pas `edit_note`: c'est deja l'icone de l'etat « Brouillon », deux
          // lignes plus loin. Deux sens pour un meme dessin sur la meme ligne.
          icon: const Icon(Icons.edit_outlined, size: 19),
        ),
        IconButton(
          tooltip: 'Export PDF',
          visualDensity: VisualDensity.compact,
          onPressed: () => onExporterPdf(_classroomId, _date),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
        ),
        IconButton(
          tooltip: 'Export Excel',
          visualDensity: VisualDensity.compact,
          onPressed: () => onExporterExcel(_classroomId, _date),
          icon: const Icon(Icons.table_view_outlined, size: 19),
        ),
      ],
    );
  }
}
