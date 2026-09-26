import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/format/montant.dart';
import '../../../core/permissions/module_permissions.dart';
import '../../../core/widgets/barre_recherche_module.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../../../core/widgets/indicateur.dart';
import '../../student_lookup/presentation/student_lookup_page.dart';
import '../domain/reports_models.dart';
import 'reports_controller.dart';

/// Les documents que l'école délivre, rassemblés.
///
/// L'écran n'en offrait que deux — un reçu et un export Excel — alors que le
/// serveur en sert une quinzaine. Les autres étaient éparpillés dans le
/// dossier de l'élève, « Notes & Bulletins » et « Enseignants », et le journal
/// de caisse n'était atteignable de nulle part, alors que celui des dépenses
/// l'était.
///
/// Deux autres défauts corrigés ici: les reçus se cherchaient et se paginaient
/// **en mémoire**, sur les encaissements entiers de l'école chargés au
/// montage; et les indicateurs comptaient les listes chargées — « Élèves »,
/// « Années », « Classes » — plutôt que ce qu'un écran de rapports doit dire.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  final _recherche = TextEditingController();

  DemandeDeRecus _demande = DemandeDeRecus.premiere;
  int? _eleveChoisi;
  int? _recuChoisi;
  bool _occupe = false;

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  void _dire(String message, {bool succes = false, bool erreur = false}) {
    if (!mounted) return;
    ForegroundNotice.show(context, message, isSuccess: succes, isError: erreur);
  }

  Future<void> _tenter(Future<void> Function() geste) async {
    setState(() => _occupe = true);
    try {
      await geste();
    } catch (_) {
      _dire('Opération impossible.', erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  /// Ouvre le dossier de l'élève, là où vivent ses pièces.
  ///
  /// Cet écran imprimait la carte scolaire lui-même, avec son propre jeu de
  /// réglages à tenir à jour en double, et sans aperçu.
  Future<void> _ouvrirLeDossier() async {
    if (_eleveChoisi == null) {
      _dire('Choisissez un élève.', erreur: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 1100,
          height: 720,
          child: StudentLookupPage(initialStudentId: _eleveChoisi),
        ),
      ),
    );
  }

  Future<void> _imprimerLeRecu() async {
    if (_recuChoisi == null) {
      _dire('Choisissez un reçu dans la liste.', erreur: true);
      return;
    }
    await _tenter(() async {
      final octets = await ref
          .read(reportsRepositoryProvider)
          .recuEnPdf(_recuChoisi!);
      await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(octets),
      );
    });
  }

  Future<void> _telecharger({
    required String nom,
    required Future<List<int>> Function() source,
    bool enPdf = false,
  }) async {
    await _tenter(() async {
      final octets = Uint8List.fromList(await source());
      if (enPdf) {
        await Printing.layoutPdf(onLayout: (_) async => octets);
        return;
      }
      final horodate = DateTime.now().millisecondsSinceEpoch;
      final fichier = '${nom}_$horodate.xlsx';
      if (kIsWeb) {
        await Printing.sharePdf(bytes: octets, filename: fichier);
        _dire('Export lancé: $fichier', succes: true);
        return;
      }
      final cible = File('${Directory.systemTemp.path}/$fichier');
      await cible.writeAsBytes(octets, flush: true);
      _dire('Export enregistré: ${cible.path}', succes: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final peutExporterDuSensible = droits.can(Capacites.exportsSensibles);
    // Les listes d'appel et du personnel sont ouvertes au personnel encadrant
    // et fermées aux familles, côté serveur. L'écran le dit plutôt que de
    // laisser un bouton refuser au clic.
    final estUneFamille = droits.role == 'parent' || droits.role == 'student';

    final contexteAsync = ref.watch(contexteDesRapportsProvider);
    final contexte = contexteAsync.valueOrNull ?? ContexteDesRapports.vide;
    final recusAsync = ref.watch(recusProvider(_demande));
    final recus = recusAsync.valueOrNull ?? PageDeRecus.vide;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        _enTete(contexteAsync.valueOrNull),
        const SizedBox(height: 14),
        _carteDuDossierEleve(contexte),
        const SizedBox(height: 14),
        _carteDesRecus(recusAsync, recus),
        const SizedBox(height: 14),
        _carteDesRegistres(
          peutExporterDuSensible: peutExporterDuSensible,
          estUneFamille: estUneFamille,
        ),
      ],
    );
  }

  Widget _enTete(ContexteDesRapports? contexte) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rapports', style: textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Reçus, registres et exports. Les pièces d\'un élève — '
                    'carte scolaire, certificat — se délivrent depuis son '
                    'dossier; les bulletins depuis « Notes & Bulletins ».',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _occupe
                  ? null
                  : () {
                      ref.invalidate(contexteDesRapportsProvider);
                      ref.invalidate(recusProvider);
                    },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Actualiser'),
            ),
          ],
        ),
        if (_occupe) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // Ce qu'un écran de rapports doit dire: combien de reçus existent
            // et pour quel montant. Il comptait les listes qu'il avait
            // chargées — élèves, années, classes.
            Indicateur(
              libelle: 'Reçus délivrables',
              valeur: contexte == null
                  ? '—'
                  : '${contexte.nombreDEncaissements}',
            ),
            Indicateur(
              libelle: 'Montant encaissé',
              valeur: contexte == null
                  ? '—'
                  : montantEnFrancs(contexte.totalEncaisse),
            ),
            Indicateur(
              libelle: 'Élèves au dossier',
              valeur: contexte == null ? '—' : '${contexte.eleves.length}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _carteDuDossierEleve(ContexteDesRapports contexte) {
    return _Encart(
      titre: 'Documents de l\'élève',
      description:
          'Carte scolaire, certificat de fréquentation et cartes de toute la '
          'classe se délivrent depuis le dossier de l\'élève, avec aperçu '
          'avant impression.',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 380,
            child: DropdownButtonFormField<int>(
              key: const Key('choix-eleve'),
              isExpanded: true,
              initialValue: _eleveChoisi,
              decoration: const InputDecoration(labelText: 'Élève'),
              items: [
                for (final eleve in contexte.eleves)
                  DropdownMenuItem(
                    value: eleve.id,
                    child: Text(
                      eleve.classe.isEmpty
                          ? eleve.libelle
                          : '${eleve.libelle} • ${eleve.classe}',
                    ),
                  ),
              ],
              onChanged: (valeur) => setState(() => _eleveChoisi = valeur),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('ouvrir-dossier-eleve'),
            onPressed: _occupe ? null : _ouvrirLeDossier,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Ouvrir le dossier élève'),
          ),
        ],
      ),
    );
  }

  Widget _carteDesRecus(AsyncValue<PageDeRecus> etat, PageDeRecus recus) {
    final textTheme = Theme.of(context).textTheme;

    return _Encart(
      titre: 'Reçu de paiement (PDF)',
      description: recus.total == 0
          ? null
          : '${recus.total} encaissement(s) — page ${recus.page} sur '
                '${recus.pages}.',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BarreRechercheModule(
            key: const Key('recherche-recus'),
            controller: _recherche,
            indication: 'Élève, matricule, référence ou montant',
            // La recherche part au serveur: elle se faisait en mémoire sur la
            // liste chargée, si bien qu'un reçu absent de cette liste était
            // introuvable.
            onChanged: (valeur) =>
                setState(() => _demande = _demande.avec(recherche: valeur)),
            onEffacer: () =>
                setState(() => _demande = _demande.avec(recherche: '')),
            rechercheEnCours: etat.isLoading,
            compact: true,
          ),
          const SizedBox(height: 10),
          if (etat.isLoading && recus.lignes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (etat.hasError)
            Text(
              'Les encaissements n\'ont pas pu être chargés.',
              style: textTheme.bodyMedium,
            )
          else if (recus.lignes.isEmpty)
            EtatVideRecherche(
              recherche: _demande.recherche,
              invitation: 'Aucun encaissement enregistré.',
              precision: 'Aucun reçu ne correspond',
              motAucun: 'reçu',
            )
          else ...[
            // `Material` transparent: l'encart est un `Container` décoré, et
            // un `ListTile` peint son fond et son onde sur le `Material` le
            // plus proche — que le cadre masquerait.
            Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  for (final recu in recus.lignes)
                    RadioListTile<int>(
                      key: ValueKey('recu-${recu.id}'),
                      value: recu.id,
                      // ignore: deprecated_member_use
                      groupValue: _recuChoisi,
                      // ignore: deprecated_member_use
                      onChanged: (valeur) =>
                          setState(() => _recuChoisi = valeur),
                      dense: true,
                      title: Text(
                        '${recu.eleve.isEmpty ? recu.matricule : recu.eleve} • '
                        '${montantEnFrancs(recu.montant)}',
                      ),
                      subtitle: Text(
                        '${recu.jour} • ${recu.typeDeFrais} • ${recu.moyen}'
                        '${recu.reference.isEmpty ? '' : ' • réf. ${recu.reference}'}',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // La pagination est celle du serveur: l'écran découpait lui-même
            // une liste qu'il avait reçue en entier.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  key: const Key('recus-page-precedente'),
                  tooltip: 'Page précédente',
                  onPressed: recus.aUnePrecedente
                      ? () => setState(
                          () => _demande = _demande.avec(page: recus.page - 1),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${recus.page} / ${recus.pages}'),
                IconButton(
                  key: const Key('recus-page-suivante'),
                  tooltip: 'Page suivante',
                  onPressed: recus.aUneSuivante
                      ? () => setState(
                          () => _demande = _demande.avec(page: recus.page + 1),
                        )
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('imprimer-recu'),
              onPressed: _occupe ? null : _imprimerLeRecu,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Imprimer le reçu sélectionné'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteDesRegistres({
    required bool peutExporterDuSensible,
    required bool estUneFamille,
  }) {
    return _Encart(
      titre: 'Registres et exports',
      description:
          'Les registres que l\'école tient, et les fichiers qu\'elle en sort.',
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (peutExporterDuSensible)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('export-paiements-excel'),
                  onPressed: _occupe
                      ? null
                      : () => _telecharger(
                          nom: 'paiements_export',
                          source: ref
                              .read(reportsRepositoryProvider)
                              .exportDesPaiementsEnExcel,
                        ),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Exporter Excel'),
                ),
                // Le journal de caisse: le serveur le sert depuis toujours et
                // rien dans l'application ne l'atteignait, alors que celui
                // des dépenses avait trouvé un écran.
                FilledButton.tonalIcon(
                  key: const Key('export-journal-caisse'),
                  onPressed: _occupe
                      ? null
                      : () => _telecharger(
                          nom: 'journal_caisse',
                          source: ref
                              .read(reportsRepositoryProvider)
                              .journalDeCaisseEnExcel,
                        ),
                  icon: const Icon(Icons.point_of_sale_outlined),
                  label: const Text('Journal de caisse'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('export-journal-depenses'),
                  onPressed: _occupe
                      ? null
                      : () => _telecharger(
                          nom: 'journal_depenses',
                          source: ref
                              .read(reportsRepositoryProvider)
                              .journalDesDepensesEnExcel,
                        ),
                  icon: const Icon(Icons.outbox_outlined),
                  label: const Text('Journal des dépenses'),
                ),
              ],
            )
          else
            const Text(
              'Export réservé à la direction et à la comptabilité.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          if (!estUneFamille) ...[
            const SizedBox(height: 14),
            Text(
              'Listes imprimables',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  key: const Key('liste-des-classes'),
                  onPressed: _occupe
                      ? null
                      : () => _telecharger(
                          nom: 'listes_de_classe',
                          enPdf: true,
                          source: ref
                              .read(reportsRepositoryProvider)
                              .listesDeClasseEnPdf,
                        ),
                  icon: const Icon(Icons.groups_2_outlined),
                  label: const Text('Listes d\'appel'),
                ),
                OutlinedButton.icon(
                  key: const Key('liste-du-personnel'),
                  onPressed: _occupe
                      ? null
                      : () => _telecharger(
                          nom: 'liste_du_personnel',
                          enPdf: true,
                          source: ref
                              .read(reportsRepositoryProvider)
                              .listeDuPersonnelEnPdf,
                        ),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Liste du personnel'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Un encart de l'écran, avec le cadre que le guide d'interface impose.
class _Encart extends StatelessWidget {
  final String titre;
  final String? description;
  final Widget enfant;

  const _Encart({required this.titre, this.description, required this.enfant});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titre, style: textTheme.titleMedium),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(description!, style: textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          enfant,
        ],
      ),
    );
  }
}
