part of 'payments_page.dart';

/// L'onglet des impayés et des relances: qui doit quoi, depuis combien de
/// temps, et ce que l'école a déjà tenté pour recouvrer.
///
/// Huit cents lignes — le plus gros des quatre onglets — au milieu d'un
/// `build` qui en comptait mille neuf cents. Les chiffres qu'il affiche sont
/// calculés par la page et lui sont passés explicitement: la liste des
/// paramètres dit exactement ce dont cet onglet dépend.
extension _OngletDesImpayes on _PaymentsPageState {
  List<Widget> ongletDesImpayes({
    required ColorScheme colorScheme,
    required List<StudentFeeItem> outstandingFees,
    required List<StudentFeeItem> visibleOutstandingFees,
    required int outstandingStart,
    required int outstandingEnd,
    required int outstandingPages,
    required double totalPaid,
    required List<_ClassKpiRow> classKpiRows,
    required List<_LateFeeAlert> filteredLateFeeAlerts,
    required int criticalLateAlerts,
    required Map<String, List<_LateFeeAlert>> classReminderGroups,
    required List<_LateStudentSummary> topLateStudents,
    required _LateTrendMetrics lateTrends,
    required List<_ReminderHistoryEntry> filteredReminderHistory,
    required List<_ReminderHistoryEntry> visibleReminderHistory,
    required int reminderStart,
    required int reminderEnd,
    required int reminderPages,
    required List<String> reminderActionOptions,
    required int safeOutstandingPage,
    required int safeReminderPage,
  }) {
    return <Widget>[
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
                'KPI par classe & alertes retard',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metricChip('Classes suivies', '${classKpiRows.length}'),
                  _metricChip('Alertes retard', '${filteredLateFeeAlerts.length}'),
                  _metricChip('Retards critiques', '$criticalLateAlerts'),
                ],
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 860;
                  final trendTile7 = Container(
                    width: compact ? double.infinity : 260,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tendance retard <= 7 jours',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Actuel: ${lateTrends.current7Count} | Précédent: ${lateTrends.previous7Count}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (lateTrends.current7Count + lateTrends.previous7Count) == 0
                              ? 0
                              : lateTrends.current7Count /
                                  (lateTrends.current7Count + lateTrends.previous7Count),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Montant actuel: ${_formatMoney(lateTrends.current7Amount)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                  final trendTile30 = Container(
                    width: compact ? double.infinity : 260,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tendance retard <= 30 jours',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Actuel: ${lateTrends.current30Count} | Précédent: ${lateTrends.previous30Count}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: (lateTrends.current30Count + lateTrends.previous30Count) == 0
                              ? 0
                              : lateTrends.current30Count /
                                  (lateTrends.current30Count + lateTrends.previous30Count),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Montant actuel: ${_formatMoney(lateTrends.current30Amount)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  );
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [trendTile7, trendTile30],
                  );
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Seuil retard:'),
                  DropdownButton<int>(
                    value: _lateAlertMinDays,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('>= 1 jour')),
                      DropdownMenuItem(value: 7, child: Text('>= 7 jours')),
                      DropdownMenuItem(value: 15, child: Text('>= 15 jours')),
                      DropdownMenuItem(value: 30, child: Text('>= 30 jours')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      majEtat(() => _lateAlertMinDays = value);
                    },
                  ),
                  FilledButton.tonalIcon(
                    onPressed: filteredLateFeeAlerts.isEmpty
                        ? null
                        : () async {
                            final csv = _buildLateAlertsCsv(filteredLateFeeAlerts);
                            await _saveTextExport(
                              content: csv,
                              fileName:
                                  'alertes_retard_${_lateAlertMinDays}j_${_timestampSuffix()}.csv',
                              dialogTitle: 'Exporter les alertes retard',
                              successMessage:
                                  'Export CSV alertes retard reussi (${filteredLateFeeAlerts.length} lignes).',
                            );
                            final totalAmount = filteredLateFeeAlerts.fold<double>(
                              0,
                              (sum, row) => sum + row.balance,
                            );
                            _recordReminderHistory(
                              action: 'Export alertes retard',
                              scope: 'Seuil ${_lateAlertMinDays}j',
                              itemCount: filteredLateFeeAlerts.length,
                              totalAmount: totalAmount,
                            );
                          },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Exporter alertes CSV'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: classReminderGroups.isEmpty
                        ? null
                        : () => _copyGlobalReminders(classReminderGroups),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Relance globale'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: classReminderGroups.isEmpty
                        ? null
                        : () async {
                            final totalAmount = classReminderGroups.values
                                .expand((rows) => rows)
                                .fold<double>(0, (sum, row) => sum + row.balance);
                            final totalItems = classReminderGroups.values
                                .fold<int>(0, (sum, rows) => sum + rows.length);
                            final csv = _buildClassRemindersCsv(classReminderGroups);
                            await _saveTextExport(
                              content: csv,
                              fileName:
                                  'relances_classes_${_lateAlertMinDays}j_${_timestampSuffix()}.csv',
                              dialogTitle: 'Exporter relances par classe',
                              successMessage:
                                  'Export CSV relances classes reussi (${classReminderGroups.length} classes).',
                            );
                            _recordReminderHistory(
                              action: 'Export relances classes',
                              scope: '${classReminderGroups.length} classes',
                              itemCount: totalItems,
                              totalAmount: totalAmount,
                            );
                          },
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Exporter relances classes'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Historique des relances',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${filteredReminderHistory.length}/${_reminderHistory.length})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: filteredReminderHistory.isEmpty
                        ? null
                        : () async {
                            final text = _reminderHistoryAsText(filteredReminderHistory);
                            await Clipboard.setData(ClipboardData(text: text));
                            _showMessage('Historique copie dans le presse-papiers.', isSuccess: true);
                          },
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: const Text('Copier'),
                  ),
                  TextButton.icon(
                    onPressed: filteredReminderHistory.isEmpty
                        ? null
                        : () async {
                            final csv = _buildReminderHistoryCsv(filteredReminderHistory);
                            await _saveTextExport(
                              content: csv,
                              fileName: 'historique_relances_${_timestampSuffix()}.csv',
                              dialogTitle: 'Exporter historique des relances',
                              successMessage:
                                  'Export CSV historique relances reussi (${filteredReminderHistory.length} lignes).',
                            );
                            final totalAmount = filteredReminderHistory.fold<double>(
                              0,
                              (sum, entry) => sum + entry.totalAmount,
                            );
                            _recordReminderHistory(
                              action: 'Export historique relances',
                              scope:
                                  'Filtre $_reminderHistoryActionFilter / ${_reminderPeriodLabel(_reminderHistoryPeriodFilter)} / tri $_reminderHistorySort',
                              itemCount: filteredReminderHistory.length,
                              totalAmount: totalAmount,
                            );
                          },
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Exporter CSV'),
                  ),
                  TextButton.icon(
                    onPressed: _reminderHistory.isEmpty
                        ? null
                        : () {
                            majEtat(() {
                              _reminderHistory.clear();
                              _reminderHistoryPage = 1;
                            });
                            unawaited(_persistReminderHistory());
                            _showMessage('Historique des relances vide.', isSuccess: true);
                          },
                    icon: const Icon(Icons.clear_all_outlined, size: 16),
                    label: const Text('Vider'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _reminderHistoryActionFilter,
                      decoration: const InputDecoration(labelText: 'Filtrer action'),
                      items: reminderActionOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(value == 'all' ? 'Toutes' : value),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        majEtat(() {
                          _reminderHistoryActionFilter = value ?? 'all';
                          _reminderHistoryPage = 1;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _reminderHistoryPeriodFilter,
                      decoration: const InputDecoration(labelText: 'Période'),
                      items: const ['all', 'today', '7d', '30d']
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value == 'all'
                                    ? 'Tout'
                                    : value == 'today'
                                    ? 'Aujourd\'hui'
                                    : value == '7d'
                                    ? '7 jours'
                                    : '30 jours',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        majEtat(() {
                          _reminderHistoryPeriodFilter = value ?? 'all';
                          _reminderHistoryPage = 1;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _reminderHistorySearchController,
                      decoration: const InputDecoration(
                        labelText: 'Recherche classe/action',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        majEtat(() {
                          _reminderHistorySearchTerm = value;
                          _reminderHistoryPage = 1;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _reminderHistorySort,
                      decoration: const InputDecoration(labelText: 'Tri'),
                      items: const [
                        DropdownMenuItem(value: 'date_desc', child: Text('Date décroissante')),
                        DropdownMenuItem(value: 'date_asc', child: Text('Date croissante')),
                        DropdownMenuItem(value: 'amount_desc', child: Text('Montant décroissant')),
                        DropdownMenuItem(value: 'amount_asc', child: Text('Montant croissant')),
                        DropdownMenuItem(value: 'count_desc', child: Text('Dossiers décroissants')),
                        DropdownMenuItem(value: 'count_asc', child: Text('Dossiers croissants')),
                      ],
                      onChanged: (value) {
                        majEtat(() {
                          _reminderHistorySort = value ?? 'date_desc';
                          _reminderHistoryPage = 1;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (filteredReminderHistory.isEmpty)
                const Text('Aucune action de relance enregistrée pour le moment.')
              else
                ...visibleReminderHistory.map((entry) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_formatDate(entry.createdAt.toIso8601String())} • ${entry.action} • ${entry.scope}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${entry.itemCount} dossier(s) • ${_formatMoney(entry.totalAmount)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  );
                }),
              if (filteredReminderHistory.isNotEmpty)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Lignes/page:'),
                        DropdownButton<int>(
                          value: _reminderHistoryPageSize,
                          items: _PaymentsPageState._reminderHistoryPageSizeOptions
                              .map(
                                (rows) => DropdownMenuItem<int>(
                                  value: rows,
                                  child: Text('$rows'),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null || value == _reminderHistoryPageSize) {
                              return;
                            }
                            majEtat(() {
                              _reminderHistoryPageSize = value;
                              _reminderHistoryPage = 1;
                            });
                          },
                        ),
                        Text(
                          'Affichage ${reminderStart + 1}-$reminderEnd sur ${filteredReminderHistory.length}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        IconButton(
                          tooltip: 'Page précédente',
                          onPressed: safeReminderPage > 1
                              ? () => majEtat(() => _reminderHistoryPage -= 1)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: 'Page suivante',
                          onPressed: safeReminderPage < reminderPages
                              ? () => majEtat(() => _reminderHistoryPage += 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              if (classKpiRows.isEmpty)
                const Text('Aucun frais disponible pour calculer les KPI.')
              else
                TableauOuFiches(
                  colonnes: const [
                    DataColumn(label: Text('Classe')),
                    DataColumn(label: Text('Élèves')),
                    DataColumn(label: Text('Frais')),
                    DataColumn(label: Text('Montant dû')),
                    DataColumn(label: Text('Montant payé')),
                    DataColumn(label: Text('Solde')),
                    DataColumn(label: Text('Taux de recouvrement')),
                    DataColumn(label: Text('Retards')),
                    DataColumn(label: Text('Relance')),
                  ],
                  lignes: classKpiRows.take(15).map((row) {
                    final isAlert = row.totalOutstanding > 0 && row.overdueCount > 0;
                    final classAlerts = filteredLateFeeAlerts
                        .where((item) => item.className == row.className)
                        .toList(growable: false);
                    return DataRow(
                      color: isAlert
                          ? WidgetStateProperty.resolveWith(
                              (_) => const Color(0xFFFEEFE8),
                            )
                          : null,
                      cells: [
                        DataCell(Text(row.className)),
                        DataCell(Text('${row.studentCount}')),
                        DataCell(Text('${row.feeCount}')),
                        DataCell(Text(_formatMoney(row.totalDue))),
                        DataCell(Text(_formatMoney(row.totalPaid))),
                        DataCell(Text(_formatMoney(row.totalOutstanding))),
                        DataCell(Text('${(row.recoveryRate * 100).toStringAsFixed(1)} %')),
                        DataCell(Text('${row.overdueCount}')),
                        DataCell(
                          classAlerts.isEmpty
                              ? const Text('-')
                              : OutlinedButton.icon(
                                  onPressed: () => _copyClassReminder(
                                    className: row.className,
                                    alerts: classAlerts,
                                  ),
                                  icon: const Icon(Icons.content_copy, size: 16),
                                  label: const Text('Relance'),
                                ),
                        ),
                      ],
                    );
                  }).toList(growable: false),
                ),
              const SizedBox(height: 8),
              Text(
                'Top 10 élèves les plus en retard',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (topLateStudents.isEmpty)
                const Text('Aucun élève en retard sur le seuil sélectionné.')
              else
                TableauOuFiches(
                  colonnes: const [
                    DataColumn(label: Text('Élève')),
                    DataColumn(label: Text('Classe')),
                    DataColumn(label: Text('Matricule')),
                    DataColumn(label: Text('Frais en retard')),
                    DataColumn(label: Text('Retard max')),
                    DataColumn(label: Text('Solde total')),
                  ],
                  lignes: topLateStudents.take(10).map((row) {
                    return DataRow(
                      cells: [
                        DataCell(Text(row.studentFullName)),
                        DataCell(Text(row.className)),
                        DataCell(Text(row.studentMatricule.isEmpty ? '-' : row.studentMatricule)),
                        DataCell(Text('${row.lateFeesCount}')),
                        DataCell(Text('${row.maxDaysLate} j')),
                        DataCell(Text(_formatMoney(row.totalBalance))),
                      ],
                    );
                  }).toList(growable: false),
                ),
              const SizedBox(height: 8),
              Text(
                'Top alertes retard',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (filteredLateFeeAlerts.isEmpty)
                const Text('Aucun retard de paiement détecté.')
              else
                ...filteredLateFeeAlerts.take(8).map((alert) {
                  final dueDate = _parseDateOnly(alert.dueDateRaw);
                  final dueLabel = dueDate == null
                      ? (alert.dueDateRaw.isEmpty ? '-' : alert.dueDateRaw)
                      : '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
                  final severityColor = alert.daysLate >= 30
                      ? const Color(0xFFB42318)
                      : alert.daysLate >= 15
                      ? const Color(0xFFB54708)
                      : const Color(0xFF2D6FD6);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: severityColor.withValues(alpha: 0.5)),
                      color: severityColor.withValues(alpha: 0.08),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: severityColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${alert.studentFullName} (${alert.studentMatricule.isEmpty ? '-' : alert.studentMatricule}) • ${alert.className}\n'
                            '${alert.feeType} • Echéance: $dueLabel • Retard: ${alert.daysLate} j • Solde: ${_formatMoney(alert.balance)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => _selectLateAlertFee(
                            alert: alert,
                            outstandingFees: outstandingFees,
                          ),
                          child: const Text('Sélectionner'),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(
                alpha: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExpansionTile(
                initiallyExpanded: _outstandingExpanded,
                onExpansionChanged: (expanded) {
                  majEtat(() => _outstandingExpanded = expanded);
                },
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Frais en attente • ${outstandingFees.length}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                childrenPadding: const EdgeInsets.only(bottom: 4),
                children: [
                  if (outstandingFees.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Aucun solde restant.'),
                    )
                  else ...[
                    Text(
                      'Affichage ${outstandingStart + 1}-$outstandingEnd sur ${outstandingFees.length} frais en attente',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: (_financeBusy || _selectedOutstandingFeeIds.isEmpty)
                              ? null
                              : () => _collectSelectedFeesInBulk(outstandingFees),
                          icon: const Icon(Icons.point_of_sale_outlined),
                          label: Text(
                            'Encaisser sélection (${_selectedOutstandingFeeIds.length})',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _selectedOutstandingFeeIds.isEmpty
                              ? null
                              : () {
                                  majEtat(() => _selectedOutstandingFeeIds.clear());
                                },
                          icon: const Icon(Icons.clear_all),
                          label: const Text('Vider la sélection'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._groupOutstandingByClass(visibleOutstandingFees).entries.map((entry) {
                      final className = entry.key;
                      final classRows = entry.value;
                      final expanded = _expandedOutstandingClasses.contains(className);
                      final classFeeIds = classRows.map((row) => row.id).toList(growable: false);
                      final allClassSelected = classFeeIds.isNotEmpty &&
                          classFeeIds.every(_selectedOutstandingFeeIds.contains);
                      final someClassSelected = classFeeIds.any(_selectedOutstandingFeeIds.contains);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: expanded,
                          onExpansionChanged: (value) {
                            majEtat(() {
                              if (value) {
                                _expandedOutstandingClasses.add(className);
                              } else {
                                _expandedOutstandingClasses.remove(className);
                              }
                            });
                          },
                          title: Row(
                            children: [
                              Checkbox(
                                tristate: true,
                                value: allClassSelected
                                    ? true
                                    : someClassSelected
                                    ? null
                                    : false,
                                onChanged: (value) {
                                  majEtat(() {
                                    if (value == true) {
                                      _selectedOutstandingFeeIds.addAll(classFeeIds);
                                    } else {
                                      _selectedOutstandingFeeIds.removeAll(classFeeIds);
                                    }
                                  });
                                },
                              ),
                              Expanded(
                                child: Text('Classe $className • ${classRows.length}'),
                              ),
                            ],
                          ),
                          children: [
                            TableauOuFiches(
                              colonnesSansLibelle: const {0},
                              colonnes: const [
                                DataColumn(label: Text('Choix')),
                                DataColumn(label: Text('Élève')),
                                DataColumn(label: Text('Matricule')),
                                DataColumn(label: Text('Type frais')),
                                DataColumn(label: Text('Montant dû')),
                                DataColumn(label: Text('Solde')),
                              ],
                              lignes: classRows
                                  .map(
                                    (fee) => DataRow(
                                      cells: [
                                        DataCell(
                                          Checkbox(
                                            value: _selectedOutstandingFeeIds.contains(fee.id),
                                            onChanged: (value) {
                                              majEtat(() {
                                                if (value == true) {
                                                  _selectedOutstandingFeeIds.add(fee.id);
                                                } else {
                                                  _selectedOutstandingFeeIds.remove(fee.id);
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                        DataCell(Text(fee.studentFullName)),
                                        DataCell(Text(fee.studentMatricule)),
                                        DataCell(Text(fee.feeType)),
                                        DataCell(Text(_formatMoney(fee.amountDue))),
                                        DataCell(Text(_formatMoney(fee.balance))),
                                      ],
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        ),
                      );
                    }),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Lignes/page:'),
                            DropdownButton<int>(
                              value: _outstandingPageSize,
                              items: _PaymentsPageState._outstandingPageSizeOptions
                                  .map(
                                    (rows) => DropdownMenuItem<int>(
                                      value: rows,
                                      child: Text('$rows'),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) {
                                if (value == null || value == _outstandingPageSize) {
                                  return;
                                }
                                majEtat(() {
                                  _outstandingPageSize = value;
                                  _outstandingPage = 1;
                                });
                              },
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 6,
                          children: [
                            IconButton(
                              tooltip: 'Page précédente',
                              onPressed: safeOutstandingPage > 1
                                  ? () => majEtat(() => _outstandingPage -= 1)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            IconButton(
                              tooltip: 'Page suivante',
                              onPressed: safeOutstandingPage < outstandingPages
                                  ? () => majEtat(() => _outstandingPage += 1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
    ];
  }
}
