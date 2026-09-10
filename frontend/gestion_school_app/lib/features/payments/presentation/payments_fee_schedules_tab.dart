part of 'payments_page.dart';

/// L'onglet des barèmes: poser une année de scolarité en un geste.
///
/// C'était le blocage le plus concret avant une rentrée. Créer les frais un
/// par un, pour cinq cents élèves avec une inscription et neuf mensualités,
/// fait cinq mille saisies: la comptable ne pouvait pas ouvrir l'année dans
/// l'application, et le faisait donc ailleurs.
///
/// Un barème décrit un frais et sa récurrence pour une classe — ou pour
/// toutes. L'appliquer crée les frais manquants, et seulement eux: l'action
/// se rejoue pour rattraper un élève inscrit en janvier sans redonner à toute
/// la classe une seconde série de mensualités.
extension _OngletDesBaremes on _PaymentsPageState {
  List<Widget> ongletDesBaremes({
    required ColorScheme colorScheme,
    required AsyncValue<List<FeeSchedule>> baremes,
  }) {
    return <Widget>[
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Barèmes de frais',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              "Le tarif d'une classe, appliqué à tous ses élèves en une fois. "
              "Réappliquer un barème ne crée que les frais manquants: c'est "
              "ainsi qu'on rattrape un élève inscrit en cours d'année.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _financeBusy ? null : _ouvrirFormulaireDeBareme,
                  icon: const Icon(Icons.playlist_add_outlined),
                  label: const Text('Nouveau barème'),
                ),
                FilledButton.icon(
                  onPressed: _financeBusy || (baremes.valueOrNull ?? []).isEmpty
                      ? null
                      : _appliquerTousLesBaremes,
                  icon: const Icon(Icons.done_all_outlined),
                  label: const Text('Tout appliquer'),
                ),
                OutlinedButton.icon(
                  onPressed: _financeBusy ? null : _importerDesFrais,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Importer des frais'),
                ),
                OutlinedButton.icon(
                  onPressed: _financeBusy ? null : _telechargerLeModeleDeFrais,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Modèle de fichier'),
                ),
                // Un élève changé de classe garde le tarif de l'ancienne, et
                // rien ne le signalait.
                OutlinedButton.icon(
                  onPressed: _financeBusy ? null : _controlerLesEcarts,
                  icon: const Icon(Icons.rule_outlined),
                  label: const Text('Contrôler les écarts'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      baremes.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (erreur, _) => _EncartDeMessage(
          icone: Icons.error_outline,
          couleur: colorScheme.error,
          titre: 'Barèmes indisponibles',
          message: _extractApiErrorMessage(erreur),
        ),
        data: (liste) {
          if (liste.isEmpty) {
            return _EncartDeMessage(
              icone: Icons.playlist_add_outlined,
              couleur: colorScheme.primary,
              titre: 'Aucun barème pour cette année',
              message:
                  "Créez-en un par classe (inscription, mensualités), relisez "
                  "l'aperçu, puis appliquez. Les frais de tous les élèves "
                  "sont créés d'un coup.",
            );
          }
          return Column(
            children: [
              for (final bareme in liste)
                _CarteDeBareme(
                  bareme: bareme,
                  occupe: _financeBusy,
                  formaterMontant: _formatMoney,
                  surApercu: () => _apercuDuBareme(bareme),
                  surAppliquer: () => _appliquerLeBareme(bareme),
                  surSupprimer: () => _supprimerLeBareme(bareme),
                ),
            ],
          );
        },
      ),
    ];
  }
}

/// Une ligne de barème, avec ce qu'elle produira et les gestes possibles.
class _CarteDeBareme extends StatelessWidget {
  final FeeSchedule bareme;
  final bool occupe;
  final String Function(num) formaterMontant;
  final VoidCallback surApercu;
  final VoidCallback surAppliquer;
  final VoidCallback surSupprimer;

  const _CarteDeBareme({
    required this.bareme,
    required this.occupe,
    required this.formaterMontant,
    required this.surApercu,
    required this.surAppliquer,
    required this.surSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recurrent = bareme.occurrences > 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  bareme.label.trim().isEmpty
                      ? bareme.feeTypeDisplay
                      : bareme.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(bareme.classroomName),
                ),
                if (recurrent)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.repeat, size: 15),
                    label: Text('${bareme.occurrences} échéances'),
                  ),
                // Un barème jamais appliqué ne produit encore aucun frais:
                // le dire évite de croire la rentrée faite.
                if (bareme.jamaisApplique)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.hourglass_empty,
                      size: 15,
                      color: scheme.onTertiaryContainer,
                    ),
                    backgroundColor: scheme.tertiaryContainer,
                    label: Text(
                      'Jamais appliqué',
                      style: TextStyle(color: scheme.onTertiaryContainer),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              recurrent
                  ? '${formaterMontant(bareme.amount)} × ${bareme.occurrences} '
                        '= ${formaterMontant(bareme.montantTotal)} par élève '
                        '• ${bareme.elevesConcernes} élève(s) concerné(s)'
                  : '${formaterMontant(bareme.amount)} par élève '
                        '• ${bareme.elevesConcernes} élève(s) concerné(s)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Première échéance: ${bareme.firstDueDate} '
              '• ${bareme.fraisGeneres} frais déjà générés',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: occupe ? null : surApercu,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Aperçu'),
                ),
                FilledButton.tonalIcon(
                  onPressed: occupe ? null : surAppliquer,
                  icon: const Icon(Icons.playlist_add_check_outlined, size: 18),
                  label: const Text('Appliquer'),
                ),
                TextButton.icon(
                  onPressed: occupe ? null : surSupprimer,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Supprimer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Un encart d'état: liste vide, ou erreur de chargement.
class _EncartDeMessage extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String titre;
  final String message;

  const _EncartDeMessage({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: couleur),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Le formulaire de création d'un barème.
///
/// Les contrôles de cohérence — échéances dans l'année scolaire, classe de la
/// bonne année, montant positif — sont tenus par le serveur, qui reste seul
/// juge. Ce formulaire se contente de ne pas envoyer ce qui est manifestement
/// incomplet, pour éviter un aller-retour inutile.
class _DialogueDeBareme extends StatefulWidget {
  final String anneeNom;
  final List<Map<String, dynamic>> classes;
  final Future<void> Function({
    required int? classroomId,
    required String feeType,
    required double amount,
    required String firstDueDate,
    required int occurrences,
    required String label,
  })
  onEnregistrer;

  /// Le lecteur d'erreur de la page: c'est lui qui sait traduire un refus du
  /// serveur en phrase lisible, et il reste le seul a le savoir.
  final String Function(Object) lireLErreur;

  const _DialogueDeBareme({
    required this.anneeNom,
    required this.classes,
    required this.onEnregistrer,
    required this.lireLErreur,
  });

  @override
  State<_DialogueDeBareme> createState() => _DialogueDeBaremeState();
}

class _DialogueDeBaremeState extends State<_DialogueDeBareme> {
  final _libelle = TextEditingController();
  final _montant = TextEditingController();
  final _echeance = TextEditingController();
  final _occurrences = TextEditingController(text: '1');

  int? _classeId;
  String _type = 'monthly';
  bool _enregistrement = false;
  String? _erreur;

  static const _types = <(String, String)>[
    ('registration', 'Frais d\'inscription'),
    ('monthly', 'Frais mensuels'),
    ('exam', 'Frais d\'examen'),
  ];

  @override
  void dispose() {
    _libelle.dispose();
    _montant.dispose();
    _echeance.dispose();
    _occurrences.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    final montant = double.tryParse(_montant.text.trim().replaceAll(',', '.'));
    final occurrences = int.tryParse(_occurrences.text.trim());
    final echeance = _echeance.text.trim();

    if (montant == null || montant <= 0) {
      setState(() => _erreur = 'Montant invalide.');
      return;
    }
    if (occurrences == null || occurrences < 1 || occurrences > 12) {
      setState(() => _erreur = 'Nombre d\'échéances attendu entre 1 et 12.');
      return;
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(echeance)) {
      setState(() => _erreur = 'Première échéance attendue au format AAAA-MM-JJ.');
      return;
    }

    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      await widget.onEnregistrer(
        classroomId: _classeId,
        feeType: _type,
        amount: montant,
        firstDueDate: echeance,
        occurrences: occurrences,
        label: _libelle.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (erreur) {
      if (!mounted) return;
      setState(() {
        _enregistrement = false;
        _erreur = widget.lireLErreur(erreur);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nouveau barème — ${widget.anneeNom}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int?>(
              isExpanded: true,
              initialValue: _classeId,
              decoration: const InputDecoration(
                labelText: 'Classe',
                helperText: 'Vide: toutes les classes de l\'année.',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Toutes les classes'),
                ),
                for (final classe in widget.classes)
                  DropdownMenuItem<int?>(
                    value: classe['id'] as int?,
                    child: Text(classe['name']?.toString() ?? '—'),
                  ),
              ],
              onChanged: _enregistrement
                  ? null
                  : (valeur) => setState(() => _classeId = valeur),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type de frais'),
              items: [
                for (final (valeur, libelle) in _types)
                  DropdownMenuItem<String>(value: valeur, child: Text(libelle)),
              ],
              onChanged: _enregistrement
                  ? null
                  : (valeur) => setState(() => _type = valeur ?? 'monthly'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _libelle,
              enabled: !_enregistrement,
              decoration: const InputDecoration(
                labelText: 'Libellé (facultatif)',
                hintText: 'Scolarité 1er versement',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _montant,
              enabled: !_enregistrement,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Montant par échéance (FCFA)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _echeance,
              enabled: !_enregistrement,
              decoration: const InputDecoration(
                labelText: 'Première échéance',
                hintText: '2025-10-05',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _occurrences,
              enabled: !_enregistrement,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nombre d\'échéances',
                helperText: '1 pour un frais unique, 9 pour neuf mensualités.',
              ),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 12),
              Text(
                _erreur!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enregistrement ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _enregistrement ? null : _enregistrer,
          child: _enregistrement
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
