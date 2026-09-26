import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/roles/libelles_des_roles.dart';
import '../../../core/widgets/barre_recherche_module.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../../../core/widgets/frozen_column_table.dart';
import '../../../core/widgets/indicateur.dart';
import '../domain/activity_log_models.dart';
import 'activity_logs_controller.dart';

/// Le journal d'audit, avec les deux questions qu'on lui pose vraiment.
///
/// « Qui a fait ça » et « qu'est-ce qui s'est passé dans les paiements » sont
/// les seules raisons d'ouvrir un journal d'audit — et aucune des deux n'était
/// posable: l'écran n'offrait que la méthode HTTP, le succès et les dates,
/// alors que le serveur filtre depuis toujours sur l'auteur, le rôle et le
/// module. Les trois filtres qui manquaient sont en tête de la barre.
///
/// Les valeurs de ces listes viennent du journal lui-même
/// (`/activity-logs/repertoire/`) et non d'une liste écrite ici, qui aurait
/// vieilli dès la première route ajoutée au serveur.
class ActivityLogsPage extends ConsumerStatefulWidget {
  const ActivityLogsPage({super.key});

  @override
  ConsumerState<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends ConsumerState<ActivityLogsPage> {
  final _recherche = TextEditingController();
  FiltreDuJournal _filtre = FiltreDuJournal.aucun;
  bool _exportEnCours = false;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _dire(String message, {bool succes = false, bool erreur = false}) {
    if (!mounted) return;
    ForegroundNotice.show(context, message, isSuccess: succes, isError: erreur);
  }

  void _appliquer(FiltreDuJournal filtre) => setState(() => _filtre = filtre);

  Future<void> _reinitialiser() async {
    _recherche.clear();
    _appliquer(FiltreDuJournal.aucun);
  }

  Future<void> _choisirUneDate({required bool depuis}) async {
    final courante = depuis ? _filtre.depuis : _filtre.jusqua;
    final choisie = await showDatePicker(
      context: context,
      initialDate: courante == null
          ? DateTime.now()
          : DateTime.tryParse(courante) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (choisie == null) return;

    final texte = choisie.toIso8601String().split('T').first;
    _appliquer(
      depuis ? _filtre.avec(depuis: texte) : _filtre.avec(jusqua: texte),
    );
  }

  /// L'export reprend exactement les filtres affichés.
  ///
  /// C'était déjà le cas et c'est la propriété à ne pas perdre: un journal
  /// exporté plus large que ce qu'on regardait ne prouve rien.
  Future<void> _exporter({required bool enExcel}) async {
    setState(() => _exportEnCours = true);
    try {
      final octets = await ref
          .read(activityLogsRepositoryProvider)
          .exporter(filtre: _filtre, enExcel: enExcel);
      final donnees = Uint8List.fromList(octets);

      if (!enExcel) {
        await Printing.layoutPdf(onLayout: (_) async => donnees);
        return;
      }

      final nom =
          'journal_activites_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      if (kIsWeb) {
        await Printing.sharePdf(bytes: donnees, filename: nom);
        _dire('Export Excel lancé: $nom', succes: true);
        return;
      }
      final fichier = File('${Directory.systemTemp.path}/$nom');
      await fichier.writeAsBytes(donnees, flush: true);
      _dire('Export Excel enregistré: ${fichier.path}', succes: true);
    } catch (_) {
      _dire('Export impossible.', erreur: true);
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lignesAsync = ref.watch(lignesDuJournalProvider(_filtre));
    final repertoireAsync = ref.watch(repertoireDuJournalProvider);
    final repertoire = repertoireAsync.valueOrNull ?? RepertoireDuJournal.vide;
    final lignes = lignesAsync.valueOrNull ?? const <LigneDuJournal>[];
    final textTheme = Theme.of(context).textTheme;

    // Nuls tant que la requête n'a pas répondu: la ligne affiche une attente
    // et non un zéro qu'on lirait comme un journal vide.
    final chargees = lignesAsync.valueOrNull?.length;
    final echecs = lignesAsync.valueOrNull
        ?.where((ligne) => !ligne.reussi)
        .length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Journal d\'activité',
                          style: textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Qui a agi, sur quel module, et ce que le serveur a '
                          'répondu. Seules les écritures y figurent.',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('export-excel'),
                        onPressed: _exportEnCours
                            ? null
                            : () => _exporter(enExcel: true),
                        icon: const Icon(Icons.table_view_outlined, size: 18),
                        label: const Text('Excel'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('export-pdf'),
                        onPressed: _exportEnCours
                            ? null
                            : () => _exporter(enExcel: false),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('PDF'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  Indicateur(
                    libelle: 'Événements',
                    valeur: chargees == null ? '—' : '$chargees',
                  ),
                  // Le chiffre qu'on cherche: ce qui a été refusé. Un journal
                  // d'audit se lit d'abord par ses échecs.
                  Indicateur(
                    libelle: 'Refusés',
                    valeur: echecs == null ? '—' : '$echecs',
                    couleur: (echecs ?? 0) > 0
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                  Indicateur(
                    libelle: 'Modules concernés',
                    valeur: '${repertoire.modules.length}',
                  ),
                ],
              ),
              if (_exportEnCours) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: BarreRechercheModule(
            controller: _recherche,
            indication: 'Rechercher (action, chemin, cible, auteur)',
            onChanged: (valeur) => _appliquer(_filtre.avec(recherche: valeur)),
            onEffacer: () => _appliquer(_filtre.avec(recherche: '')),
            rechercheEnCours: lignesAsync.isLoading,
            actions: [
              // Les trois filtres qui manquaient, en tête: ce sont eux qu'on
              // vient chercher.
              _Choix<int>(
                cle: 'filtre-auteur',
                libelle: 'Auteur',
                largeur: 250,
                valeur: _filtre.auteurId,
                entrees: [
                  for (final auteur in repertoire.auteurs)
                    (auteur.id, '${auteur.nom} — ${roleEnClair(auteur.role)}'),
                ],
                onChanged: (valeur) => _appliquer(
                  valeur == null
                      ? _filtre.avec(viderAuteur: true)
                      : _filtre.avec(auteurId: valeur),
                ),
              ),
              _Choix<String>(
                cle: 'filtre-role',
                libelle: 'Rôle',
                largeur: 190,
                valeur: _filtre.role,
                entrees: [
                  for (final entree in libellesDesRoles.entries)
                    (entree.key, entree.value),
                ],
                onChanged: (valeur) => _appliquer(
                  valeur == null
                      ? _filtre.avec(viderRole: true)
                      : _filtre.avec(role: valeur),
                ),
              ),
              _Choix<String>(
                cle: 'filtre-module',
                libelle: 'Module',
                largeur: 200,
                valeur: _filtre.module,
                entrees: [
                  for (final module in repertoire.modules) (module, module),
                ],
                onChanged: (valeur) => _appliquer(
                  valeur == null
                      ? _filtre.avec(viderModule: true)
                      : _filtre.avec(module: valeur),
                ),
              ),
              _Choix<String>(
                cle: 'filtre-methode',
                libelle: 'Méthode',
                largeur: 150,
                valeur: _filtre.methode,
                entrees: const [
                  ('POST', 'POST'),
                  ('PUT', 'PUT'),
                  ('PATCH', 'PATCH'),
                  ('DELETE', 'DELETE'),
                ],
                onChanged: (valeur) => _appliquer(
                  valeur == null
                      ? _filtre.avec(viderMethode: true)
                      : _filtre.avec(methode: valeur),
                ),
              ),
              _Choix<bool>(
                cle: 'filtre-issue',
                libelle: 'Issue',
                largeur: 160,
                valeur: _filtre.reussi,
                entrees: const [(true, 'Acceptés'), (false, 'Refusés')],
                onChanged: (valeur) => _appliquer(
                  valeur == null
                      ? _filtre.avec(viderReussite: true)
                      : _filtre.avec(reussi: valeur),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('filtre-depuis'),
                onPressed: () => _choisirUneDate(depuis: true),
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(_filtre.depuis ?? 'Depuis'),
              ),
              OutlinedButton.icon(
                key: const Key('filtre-jusqua'),
                onPressed: () => _choisirUneDate(depuis: false),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(_filtre.jusqua ?? 'Jusqu\'au'),
              ),
              _Choix<TriDuJournal>(
                cle: 'filtre-tri',
                libelle: 'Trier par',
                largeur: 230,
                valeur: _filtre.tri,
                avecTous: false,
                entrees: [
                  for (final tri in TriDuJournal.values) (tri, tri.libelle),
                ],
                onChanged: (valeur) => _appliquer(
                  _filtre.avec(tri: valeur ?? TriDuJournal.plusRecentDAbord),
                ),
              ),
              if (!_filtre.estVide)
                TextButton.icon(
                  key: const Key('reinitialiser-filtres'),
                  onPressed: _reinitialiser,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Réinitialiser'),
                ),
            ],
          ),
        ),

        Expanded(
          child: lignesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (erreur, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Le journal n\'a pas pu être chargé.',
                  style: textTheme.bodyMedium,
                ),
              ),
            ),
            data: (_) {
              if (lignes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: EtatVideRecherche(
                    recherche: _filtre.recherche,
                    invitation: 'Aucune activité enregistrée.',
                    precision: 'Aucun événement ne correspond',
                    motAucun: 'événement',
                  ),
                );
              }
              return _Tableau(
                lignes: lignes,
                onOuvrir: (ligne) => _ouvrirLeDetail(context, ligne),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _ouvrirLeDetail(BuildContext context, LigneDuJournal ligne) {
    return showDialog<void>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: Text(ligne.action.isEmpty ? 'Événement' : ligne.action),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entree in <(String, String)>[
                  ('Quand', '${ligne.jour} à ${ligne.heure}'),
                  ('Auteur', ligne.auteur),
                  ('Rôle', roleEnClair(ligne.role)),
                  ('Module', ligne.module),
                  ('Méthode', ligne.methode),
                  ('Chemin', ligne.chemin),
                  ('Cible', ligne.cible),
                  ('Réponse', '${ligne.statutHttp}'),
                  ('Adresse IP', ligne.adresseIp),
                  if (ligne.etablissement.isNotEmpty)
                    ('Établissement', ligne.etablissement),
                  if (ligne.details.isNotEmpty) ('Détails', ligne.details),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            entree.$1,
                            style: Theme.of(contexte).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            entree.$2.isEmpty ? '—' : entree.$2,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexte).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

/// Un filtre déroulant, avec son entrée « tous » et sa largeur.
///
/// Sept filtres écrits à la main faisaient sept fois le même `Dropdown` de
/// quinze lignes, et la première entrée n'y valait pas toujours « aucun
/// filtre » de la même manière.
class _Choix<T> extends StatelessWidget {
  final String cle;
  final String libelle;
  final double largeur;
  final T? valeur;
  final List<(T, String)> entrees;
  final ValueChanged<T?> onChanged;
  final bool avecTous;

  const _Choix({
    required this.cle,
    required this.libelle,
    required this.largeur,
    required this.valeur,
    required this.entrees,
    required this.onChanged,
    this.avecTous = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largeur,
      child: DropdownButtonFormField<T?>(
        key: Key(cle),
        isExpanded: true,
        isDense: true,
        initialValue: valeur,
        decoration: InputDecoration(
          labelText: libelle,
          border: const OutlineInputBorder(),
        ),
        items: [
          if (avecTous) const DropdownMenuItem(value: null, child: Text('Tous')),
          for (final entree in entrees)
            DropdownMenuItem(value: entree.$1, child: Text(entree.$2)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _Tableau extends StatelessWidget {
  final List<LigneDuJournal> lignes;
  final ValueChanged<LigneDuJournal> onOuvrir;

  const _Tableau({required this.lignes, required this.onOuvrir});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget cellule(String texte) => Text(
      texte.isEmpty ? '—' : texte,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodySmall,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: FrozenColumnTable(
        frozenColumnWidth: 120,
        // La colonne « Quand » porte le jour puis l'heure, sur deux lignes:
        // la hauteur par défaut ne laisse la place que pour une, et le
        // rendu déborde de sa cellule (16 px, selon l'interligne du thème).
        minRowHeight: 84,
        frozenHeader: const Text('Quand'),
        headers: const [
          Text('Auteur'),
          Text('Rôle'),
          Text('Action'),
          Text('Module'),
          Text('Méthode'),
          Text('Réponse'),
          Text('Chemin'),
          Text(''),
        ],
        frozenCells: [
          for (final ligne in lignes)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(ligne.jour, style: textTheme.bodySmall),
                Text(
                  ligne.heure,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
        ],
        rows: [
          for (final ligne in lignes)
            [
              cellule(ligne.auteur),
              cellule(roleEnClair(ligne.role)),
              cellule(ligne.action),
              cellule(ligne.module),
              cellule(ligne.methode),
              // L'issue se lit à la couleur avant de se lire au chiffre.
              Row(
                children: [
                  Icon(
                    ligne.reussi
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 16,
                    color: ligne.reussi ? null : scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text('${ligne.statutHttp}', style: textTheme.bodySmall),
                ],
              ),
              cellule(ligne.chemin),
              TextButton(
                key: ValueKey('detail-${ligne.id}'),
                onPressed: () => onOuvrir(ligne),
                child: const Text('Détail'),
              ),
            ],
        ],
      ),
    );
  }
}
