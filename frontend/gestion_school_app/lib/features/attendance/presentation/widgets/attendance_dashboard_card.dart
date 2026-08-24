import 'package:flutter/material.dart';

import '../../domain/attendance_stats.dart';

/// En-tete de l'emargement des eleves: ce que dit le mois, et de quel
/// perimetre on parle.
///
/// La rubrique ouvrait sur un ExpansionTile replie nomme « Statistiques
/// mensuelles » -- ni titre, ni bouton d'actualisation, ni indication de
/// l'etablissement ou de la fraicheur des donnees, la ou « Gestion des
/// eleves » et « Enseignants » ouvrent tous deux sur un tableau de bord.
/// Trois ecrans du meme logiciel n'avaient pas la meme entree en matiere.
///
/// Ses entrees sont explicites -- compteurs, libelles -- ce qui la rend
/// affichable sans monter la page entiere ni ses appels reseau.
class AttendanceDashboardCard extends StatelessWidget {
  /// Nul tant que le serveur n'a pas repondu.
  final AttendanceMonthlyStats? stats;

  /// Renseigne quand les statistiques ont echoue: mieux vaut le dire que
  /// d'afficher des zeros qu'on lirait comme un mois sans absence.
  final String? statsError;

  final int classCount;
  final String scopeLabel;
  final String refreshLabel;
  final bool isCompactLayout;
  final bool loading;

  /// Le profil connecte consulte sans saisir.
  final bool readOnly;

  final VoidCallback onRefresh;

  /// Courbe du mois, repliee: elle decrit le mois ecoule, quand la feuille
  /// d'appel juste en dessous est le geste du jour.
  final Widget? courbe;

  const AttendanceDashboardCard({
    super.key,
    required this.stats,
    required this.statsError,
    required this.classCount,
    required this.scopeLabel,
    required this.refreshLabel,
    required this.isCompactLayout,
    required this.loading,
    required this.readOnly,
    required this.onRefresh,
    this.courbe,
  });

  static ButtonStyle compactActionStyle() {
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.75),
              scheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompactLayout ? 12 : 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _titre(context, textTheme),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: _chips(context)),
              const SizedBox(height: 12),
              _compteurs(context),
              if (loading) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              if (courbe != null) ...[
                const SizedBox(height: 4),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text('Courbe du mois', style: textTheme.labelLarge),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    children: [courbe!],
                  ),
                ),
              ],
              if (readOnly) ...[
                const SizedBox(height: 8),
                Text(
                  'Mode lecture seule: ce profil consulte l’émargement sans le saisir.',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _titre(BuildContext context, TextTheme textTheme) {
    final titre = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Émargement élèves',
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          'La feuille d’appel du jour, classe par classe.',
          style: textTheme.bodySmall,
        ),
      ],
    );
    final actualiser = FilledButton.tonalIcon(
      style: compactActionStyle(),
      onPressed: loading ? null : onRefresh,
      icon: const Icon(Icons.sync),
      label: const Text('Actualiser'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titre,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: actualiser),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titre),
            const SizedBox(width: 10),
            actualiser,
          ],
        );
      },
    );
  }

  List<Widget> _chips(BuildContext context) {
    final mois = stats?.month ?? '';
    return [
      _Chip(
        icon: Icons.calendar_month_outlined,
        label: mois.isEmpty ? 'Mois: -' : 'Mois: $mois',
      ),
      _Chip(icon: Icons.class_outlined, label: '$classCount classes'),
      _Chip(icon: Icons.apartment_outlined, label: scopeLabel, maxWidth: 320),
      _Chip(icon: Icons.schedule_outlined, label: refreshLabel),
    ];
  }

  Widget _compteurs(BuildContext context) {
    final erreur = statsError;
    if (erreur != null) {
      return _Avertissement(message: erreur);
    }

    final valeurs = stats;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _Compteur(
          libelle: 'Enregistrements',
          valeur: valeurs?.totalRecords,
          icone: Icons.fact_check_outlined,
        ),
        _Compteur(
          libelle: 'Absences',
          valeur: valeurs?.absences,
          icone: Icons.person_off_outlined,
          alerte: (valeurs?.absences ?? 0) > 0,
        ),
        _Compteur(
          libelle: 'Retards',
          valeur: valeurs?.lates,
          icone: Icons.running_with_errors_outlined,
        ),
        _Compteur(
          libelle: 'Justificatifs',
          valeur: valeurs?.justifications,
          icone: Icons.task_outlined,
        ),
      ],
    );
  }
}

class _Compteur extends StatelessWidget {
  final String libelle;

  /// Nul tant que le serveur n'a pas repondu: un tiret ne se lit pas comme
  /// un zero.
  final int? valeur;

  final IconData icone;
  final bool alerte;

  const _Compteur({
    required this.libelle,
    required this.valeur,
    required this.icone,
    this.alerte = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 152,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icone, size: 15, color: scheme.primary),
              const SizedBox(width: 6),
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
          const SizedBox(height: 4),
          Text(
            valeur?.toString() ?? '—',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alerte ? scheme.error : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avertissement extends StatelessWidget {
  final String message;

  const _Avertissement({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double maxWidth;

  const _Chip({required this.icon, required this.label, this.maxWidth = 220});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
