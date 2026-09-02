import 'package:flutter/material.dart';

/// Etat d'un élève sur la feuille d'appel.
///
/// « Present » n'existe pas en base: c'est l'absence de `is_absent`. Le retard
/// reste independant, un eleve en retard etant present -- les fondre en trois
/// etats exclusifs aurait change le sens des statistiques existantes.
enum PresenceEleve { present, absent }

/// La liste d'appel d'une classe: une ligne par eleve.
///
/// Chaque eleve occupait auparavant une carte entiere -- nom, interrupteur
/// « Absent » pleine largeur, interrupteur « Retard », champ « Motif » --
/// soit environ 200 pixels. Faire l'appel dans une classe de trente demandait
/// de parcourir six ecrans et d'actionner soixante interrupteurs.
class AttendanceSheetList extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  /// Faux quand la fiche est verrouillee ou que le profil ne peut pas ecrire.
  final bool editable;

  final void Function(Map<String, dynamic> ligne, PresenceEleve etat)
  onPresenceChanged;
  final void Function(Map<String, dynamic> ligne, bool enRetard) onRetardChanged;
  final void Function(Map<String, dynamic> ligne, String motif) onMotifChanged;
  final VoidCallback onToutPresent;

  /// Ouvre le justificatif d'une ligne: deposer, remplacer, retirer.
  ///
  /// Nul quand le profil ne peut pas ecrire: la colonne montre alors l'etat
  /// sans le proposer a la modification.
  final void Function(Map<String, dynamic> ligne)? onJustificatif;

  const AttendanceSheetList({
    super.key,
    required this.items,
    required this.editable,
    required this.onPresenceChanged,
    required this.onRetardChanged,
    required this.onMotifChanged,
    required this.onToutPresent,
    this.onJustificatif,
  });

  static bool estAbsent(Map<String, dynamic> ligne) => ligne['is_absent'] == true;
  static bool estEnRetard(Map<String, dynamic> ligne) => ligne['is_late'] == true;
  static bool estJustifie(Map<String, dynamic> ligne) => ligne['has_proof'] == true;

  /// Une ligne non encore enregistree n'a pas d'identifiant a qui attacher
  /// un fichier: on justifie une absence qui existe.
  static int? identifiant(Map<String, dynamic> ligne) {
    final brut = ligne['attendance_id'];
    if (brut is int) return brut;
    return int.tryParse(brut?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Bandeau(
          items: items,
          editable: editable,
          onToutPresent: onToutPresent,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            // Sous 720, une ligne de tableau ne tient pas: on empile des
            // lignes courtes plutot que d'imposer un defilement lateral.
            final compact = constraints.maxWidth < 720;
            return Column(
              children: [
                if (!compact) _EnTeteColonnes(),
                for (var index = 0; index < items.length; index++)
                  _Ligne(
                    rang: index + 1,
                    ligne: items[index],
                    editable: editable,
                    compact: compact,
                    onPresenceChanged: onPresenceChanged,
                    onRetardChanged: onRetardChanged,
                    onMotifChanged: onMotifChanged,
                    onJustificatif: onJustificatif,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Bandeau extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool editable;
  final VoidCallback onToutPresent;

  const _Bandeau({
    required this.items,
    required this.editable,
    required this.onToutPresent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final absents = items.where(AttendanceSheetList.estAbsent).length;
    final retards = items.where(AttendanceSheetList.estEnRetard).length;
    final presents = items.length - absents;
    final justifies = items
        .where(AttendanceSheetList.estAbsent)
        .where(AttendanceSheetList.estJustifie)
        .length;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // L'appel consiste a relever deux ou trois absents, pas a cocher
        // trente presents un par un.
        OutlinedButton.icon(
          onPressed: (editable && items.isNotEmpty) ? onToutPresent : null,
          icon: const Icon(Icons.done_all, size: 18),
          label: const Text('Tout présent'),
        ),
        Text(
          '$presents présent${presents > 1 ? 's' : ''}'
          '  ·  $absents absent${absents > 1 ? 's' : ''}'
          '${justifies > 0 ? ' (dont $justifies justifié${justifies > 1 ? 's' : ''})' : ''}'
          '${retards > 0 ? '  ·  $retards retard${retards > 1 ? 's' : ''}' : ''}',
          style: textTheme.titleSmall?.copyWith(
            color: absents > 0 ? scheme.error : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EnTeteColonnes extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('N°', style: style)),
          Expanded(child: Text('ÉLÈVE', style: style)),
          SizedBox(width: 78, child: Text('PRÉSENT', style: style)),
          SizedBox(width: 70, child: Text('ABSENT', style: style)),
          SizedBox(width: 66, child: Text('RETARD', style: style)),
          SizedBox(width: 156, child: Text('MOTIF', style: style)),
          SizedBox(width: 54, child: Text('JUSTIF.', style: style)),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  final int rang;
  final Map<String, dynamic> ligne;
  final bool editable;
  final bool compact;
  final void Function(Map<String, dynamic>, PresenceEleve) onPresenceChanged;
  final void Function(Map<String, dynamic>, bool) onRetardChanged;
  final void Function(Map<String, dynamic>, String) onMotifChanged;
  final void Function(Map<String, dynamic>)? onJustificatif;

  const _Ligne({
    required this.rang,
    required this.ligne,
    required this.editable,
    required this.compact,
    required this.onPresenceChanged,
    required this.onRetardChanged,
    required this.onMotifChanged,
    required this.onJustificatif,
  });

  String get _nom {
    final nom = (ligne['student_full_name'] ?? '').toString().trim();
    return nom.isEmpty ? 'Eleve' : nom;
  }

  String get _matricule => (ligne['student_matricule'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final absent = AttendanceSheetList.estAbsent(ligne);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: compact ? 8 : 4),
      decoration: BoxDecoration(
        // Une ligne absente se repere d'un coup d'oeil sur trente.
        color: absent ? scheme.errorContainer.withValues(alpha: 0.28) : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: compact ? _buildCompact(context, scheme) : _buildLarge(context),
    );
  }

  Widget _buildLarge(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 32, child: Text('$rang')),
        Expanded(child: _identite(context)),
        SizedBox(width: 78, child: _radio(context, PresenceEleve.present)),
        SizedBox(width: 70, child: _radio(context, PresenceEleve.absent)),
        SizedBox(width: 66, child: _caseRetard()),
        SizedBox(width: 156, child: _champMotif(context)),
        SizedBox(width: 54, child: _boutonJustificatif(context)),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 26, child: Text('$rang')),
            Expanded(child: _identite(context)),
            _boutonCompact('P', PresenceEleve.present, scheme),
            const SizedBox(width: 4),
            _boutonCompact('A', PresenceEleve.absent, scheme),
            const SizedBox(width: 4),
            _caseRetard(compactLabel: 'R'),
          ],
        ),
        if (AttendanceSheetList.estAbsent(ligne))
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 4),
            child: Row(
              children: [
                Expanded(child: _champMotif(context)),
                _boutonJustificatif(context),
              ],
            ),
          ),
      ],
    );
  }

  Widget _identite(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _nom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (_matricule.isNotEmpty)
          Text(
            _matricule,
            style: textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  /// Bouton d'etat exclusif.
  ///
  /// `Radio` aurait convenu, mais son couple groupValue/onChanged est
  /// deprecie depuis Flutter 3.32 au profit d'un `RadioGroup` ancetre, qui
  /// obligerait a envelopper chaque ligne. Un bouton a deux etats dit la meme
  /// chose et se touche mieux au doigt.
  Widget _radio(BuildContext context, PresenceEleve valeur) {
    final scheme = Theme.of(context).colorScheme;
    final actif =
        (AttendanceSheetList.estAbsent(ligne)
            ? PresenceEleve.absent
            : PresenceEleve.present) ==
        valeur;
    final couleur = valeur == PresenceEleve.absent
        ? scheme.error
        : scheme.primary;

    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        tooltip: valeur == PresenceEleve.absent ? 'Absent' : 'Présent',
        visualDensity: VisualDensity.compact,
        onPressed: editable ? () => onPresenceChanged(ligne, valeur) : null,
        icon: Icon(
          actif ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 20,
          color: actif ? couleur : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _boutonCompact(
    String lettre,
    PresenceEleve valeur,
    ColorScheme scheme,
  ) {
    final actif =
        (AttendanceSheetList.estAbsent(ligne)
            ? PresenceEleve.absent
            : PresenceEleve.present) ==
        valeur;

    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: actif ? scheme.primary : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: editable ? () => onPresenceChanged(ligne, valeur) : null,
          child: Center(
            child: Text(
              lettre,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: actif ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _caseRetard({String? compactLabel}) {
    final case_ = Checkbox(
      value: AttendanceSheetList.estEnRetard(ligne),
      onChanged: editable
          ? (valeur) => onRetardChanged(ligne, valeur ?? false)
          : null,
    );
    if (compactLabel == null) return case_;
    return Tooltip(message: 'Retard', child: case_);
  }

  /// Etat du justificatif, et acces au depot quand il est possible.
  ///
  /// Le champ existait en base depuis l'origine et les statistiques
  /// comptaient deja les justificatifs, mais aucun ecran ne permettait d'en
  /// deposer un: le compteur affichait zero en permanence.
  Widget _boutonJustificatif(BuildContext context) {
    if (!AttendanceSheetList.estAbsent(ligne)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final justifie = AttendanceSheetList.estJustifie(ligne);
    final identifiant = AttendanceSheetList.identifiant(ligne);

    // Une absence pas encore enregistree n'a rien a quoi attacher un fichier.
    if (identifiant == null) {
      return Tooltip(
        message: 'Enregistrez la fiche avant de joindre un justificatif',
        child: Icon(
          Icons.attach_file,
          size: 18,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      );
    }

    final nom = (ligne['proof_name'] ?? '').toString();
    return IconButton(
      tooltip: justifie
          ? (nom.isEmpty ? 'Justificatif joint' : 'Justificatif: $nom')
          : 'Joindre un justificatif',
      visualDensity: VisualDensity.compact,
      onPressed: onJustificatif == null ? null : () => onJustificatif!(ligne),
      icon: Icon(
        justifie ? Icons.task_outlined : Icons.attach_file,
        size: 19,
        color: justifie ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _champMotif(BuildContext context) {
    // Une colonne motif vide sur vingt-huit lignes n'apprend rien: elle
    // n'apparait que pour les eleves absents.
    if (!AttendanceSheetList.estAbsent(ligne)) {
      return const SizedBox.shrink();
    }
    return TextFormField(
      key: ValueKey('motif-${ligne['student']}'),
      initialValue: (ligne['reason'] ?? '').toString(),
      enabled: editable,
      style: Theme.of(context).textTheme.bodySmall,
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Motif',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      onChanged: (valeur) => onMotifChanged(ligne, valeur),
    );
  }
}
