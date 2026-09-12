part of 'payments_page.dart';

/// Les impayés vus comme un travail de recouvrement: qui est en retard, de
/// combien de jours, ce qu'on lui a déjà écrit et quand.
///
/// Quatre cents lignes de calcul et de mise en forme de texte, au milieu d'un
/// état qui pilote par ailleurs la caisse, la paie et les dépenses. Rien ici
/// ne touche à la base: ce sont des relevés tirés des frais déjà chargés, et
/// des messages prêts à coller dans WhatsApp. C'est ce qui les rend
/// vérifiables isolément.
extension _Relances on _PaymentsPageState {
  List<_LateFeeAlert> _buildLateFeeAlerts(List<StudentFeeItem> fees) {
    final today = _dayStart(DateTime.now());
    final alerts = <_LateFeeAlert>[];
    for (final fee in fees) {
      if (fee.balance <= 0) {
        continue;
      }
      final dueDate = _parseDateOnly(fee.dueDate);
      if (dueDate == null || !dueDate.isBefore(today)) {
        continue;
      }

      alerts.add(
        _LateFeeAlert(
          feeId: fee.id,
          className: _classLabel(fee.classroomName),
          studentFullName: fee.studentFullName,
          studentMatricule: fee.studentMatricule,
          feeType: fee.feeType,
          dueDateRaw: fee.dueDate,
          daysLate: today.difference(dueDate).inDays,
          balance: fee.balance,
        ),
      );
    }

    alerts.sort((a, b) {
      final byDays = b.daysLate.compareTo(a.daysLate);
      if (byDays != 0) {
        return byDays;
      }
      return b.balance.compareTo(a.balance);
    });
    return alerts;
  }

  List<_LateFeeAlert> _applyLateAlertThreshold(List<_LateFeeAlert> rows) {
    return rows.where((row) => row.daysLate >= _lateAlertMinDays).toList(growable: false);
  }

  String _buildLateAlertsCsv(List<_LateFeeAlert> rows) {
    final buffer = StringBuffer();
    buffer.writeln('fee_id,classe,eleve,matricule,type_frais,echeance,jours_retard,solde');

    for (final row in rows) {
      buffer.writeln(
        [
          _csvEscape(row.feeId.toString()),
          _csvEscape(row.className),
          _csvEscape(row.studentFullName),
          _csvEscape(row.studentMatricule),
          _csvEscape(row.feeType),
          _csvEscape(row.dueDateRaw),
          _csvEscape(row.daysLate.toString()),
          _csvEscape(row.balance.toStringAsFixed(0)),
        ].join(','),
      );
    }

    return buffer.toString();
  }

  String _buildClassReminderMessage({
    required String className,
    required List<_LateFeeAlert> alerts,
  }) {
    final buffer = StringBuffer();
    final total = alerts.fold<double>(0, (sum, row) => sum + row.balance);
    buffer.writeln('Objet: Relance paiement - Classe $className');
    buffer.writeln('');
    buffer.writeln('Bonjour,');
    buffer.writeln(
      'Merci de regulariser les frais en retard pour la classe $className. Montant total en attente: ${_formatMoney(total)}.',
    );
    buffer.writeln('');
    buffer.writeln('Détails prioritaires:');
    for (final alert in alerts.take(12)) {
      buffer.writeln(
        '- ${alert.studentFullName} (${alert.studentMatricule.isEmpty ? '-' : alert.studentMatricule}) | ${alert.feeType} | ${alert.daysLate} j de retard | ${_formatMoney(alert.balance)}',
      );
    }
    if (alerts.length > 12) {
      buffer.writeln('- ... et ${alerts.length - 12} autre(s) dossier(s).');
    }
    buffer.writeln('');
    buffer.writeln('Cordialement,');
    buffer.writeln('Service Finances');
    return buffer.toString();
  }

  List<_LateStudentSummary> _buildTopLateStudents(List<_LateFeeAlert> alerts) {
    final grouped = <String, _LateStudentSummary>{};
    for (final alert in alerts) {
      final key = alert.studentMatricule.trim().isEmpty
          ? '${alert.className}|${alert.studentFullName}'
          : alert.studentMatricule.trim();
      final previous = grouped[key];
      if (previous == null) {
        grouped[key] = _LateStudentSummary(
          studentKey: key,
          studentFullName: alert.studentFullName,
          studentMatricule: alert.studentMatricule,
          className: alert.className,
          lateFeesCount: 1,
          maxDaysLate: alert.daysLate,
          totalBalance: alert.balance,
        );
        continue;
      }
      grouped[key] = _LateStudentSummary(
        studentKey: key,
        studentFullName: previous.studentFullName,
        studentMatricule: previous.studentMatricule,
        className: previous.className,
        lateFeesCount: previous.lateFeesCount + 1,
        maxDaysLate: alert.daysLate > previous.maxDaysLate ? alert.daysLate : previous.maxDaysLate,
        totalBalance: previous.totalBalance + alert.balance,
      );
    }

    final rows = grouped.values.toList(growable: false);
    rows.sort((a, b) {
      final byDays = b.maxDaysLate.compareTo(a.maxDaysLate);
      if (byDays != 0) {
        return byDays;
      }
      return b.totalBalance.compareTo(a.totalBalance);
    });
    return rows;
  }

  _LateTrendMetrics _buildLateTrendMetrics(List<StudentFeeItem> fees) {
    final today = _dayStart(DateTime.now());

    var current7Count = 0;
    var previous7Count = 0;
    var current30Count = 0;
    var previous30Count = 0;
    var current7Amount = 0.0;
    var previous7Amount = 0.0;
    var current30Amount = 0.0;
    var previous30Amount = 0.0;

    for (final fee in fees) {
      if (fee.balance <= 0) {
        continue;
      }
      final dueDate = _parseDateOnly(fee.dueDate);
      if (dueDate == null || !dueDate.isBefore(today)) {
        continue;
      }

      final daysLate = today.difference(dueDate).inDays;

      if (daysLate <= 7) {
        current7Count += 1;
        current7Amount += fee.balance;
      } else if (daysLate <= 14) {
        previous7Count += 1;
        previous7Amount += fee.balance;
      }

      if (daysLate <= 30) {
        current30Count += 1;
        current30Amount += fee.balance;
      } else if (daysLate <= 60) {
        previous30Count += 1;
        previous30Amount += fee.balance;
      }
    }

    return _LateTrendMetrics(
      current7Count: current7Count,
      previous7Count: previous7Count,
      current30Count: current30Count,
      previous30Count: previous30Count,
      current7Amount: current7Amount,
      previous7Amount: previous7Amount,
      current30Amount: current30Amount,
      previous30Amount: previous30Amount,
    );
  }

  Future<void> _copyClassReminder({
    required String className,
    required List<_LateFeeAlert> alerts,
  }) async {
    final message = _buildClassReminderMessage(className: className, alerts: alerts);
    final total = alerts.fold<double>(0, (sum, row) => sum + row.balance);
    await Clipboard.setData(ClipboardData(text: message));
    _recordReminderHistory(
      action: 'Relance classe',
      scope: className,
      itemCount: alerts.length,
      totalAmount: total,
    );
    _showMessage(
      'Message de relance copie pour la classe $className (${alerts.length} dossier(s)).',
      isSuccess: true,
    );
  }

  void _recordReminderHistory({
    required String action,
    required String scope,
    required int itemCount,
    required double totalAmount,
  }) {
    majEtat(() {
      _reminderHistory.insert(
        0,
        _ReminderHistoryEntry(
          createdAt: DateTime.now(),
          action: action,
          scope: scope,
          itemCount: itemCount,
          totalAmount: totalAmount,
        ),
      );
      if (_reminderHistory.length > 30) {
        _reminderHistory.removeRange(30, _reminderHistory.length);
      }
      _reminderHistoryPage = 1;
    });
    unawaited(_persistReminderHistory());
  }

  String _reminderHistoryAsText([List<_ReminderHistoryEntry>? rows]) {
    final source = rows ?? _reminderHistory;
    if (source.isEmpty) {
      return 'Aucun historique de relance.';
    }
    final buffer = StringBuffer();
    for (final entry in source) {
      buffer.writeln(
        '${_formatDate(entry.createdAt.toIso8601String())} | ${entry.action} | ${entry.scope} | ${entry.itemCount} dossier(s) | ${_formatMoney(entry.totalAmount)}',
      );
    }
    return buffer.toString();
  }

  String _buildReminderHistoryCsv(List<_ReminderHistoryEntry> rows) {
    final buffer = StringBuffer();
    buffer.writeln('date,action,scope,nombre_dossiers,montant_total');
    for (final entry in rows) {
      buffer.writeln(
        [
          _csvEscape(entry.createdAt.toIso8601String()),
          _csvEscape(entry.action),
          _csvEscape(entry.scope),
          _csvEscape(entry.itemCount.toString()),
          _csvEscape(entry.totalAmount.toStringAsFixed(0)),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  List<_ReminderHistoryEntry> _filteredReminderHistory() {
    final text = _reminderHistorySearchTerm.trim().toLowerCase();
    final rows = _reminderHistory.where((entry) {
      if (_reminderHistoryActionFilter != 'all' && entry.action != _reminderHistoryActionFilter) {
        return false;
      }
      if (!_matchesReminderPeriod(entry.createdAt)) {
        return false;
      }
      if (text.isEmpty) {
        return true;
      }
      return entry.action.toLowerCase().contains(text) || entry.scope.toLowerCase().contains(text);
    }).toList(growable: false);

    rows.sort((left, right) {
      switch (_reminderHistorySort) {
        case 'date_asc':
          return left.createdAt.compareTo(right.createdAt);
        case 'amount_desc':
          return right.totalAmount.compareTo(left.totalAmount);
        case 'amount_asc':
          return left.totalAmount.compareTo(right.totalAmount);
        case 'count_desc':
          return right.itemCount.compareTo(left.itemCount);
        case 'count_asc':
          return left.itemCount.compareTo(right.itemCount);
        case 'date_desc':
        default:
          return right.createdAt.compareTo(left.createdAt);
      }
    });

    return rows;
  }

  bool _matchesReminderPeriod(DateTime value) {
    if (_reminderHistoryPeriodFilter == 'all') {
      return true;
    }
    final now = _dayStart(DateTime.now());
    final target = _dayStart(value.toLocal());
    if (_reminderHistoryPeriodFilter == 'today') {
      return target == now;
    }
    if (_reminderHistoryPeriodFilter == '7d') {
      final start = now.subtract(const Duration(days: 6));
      return !target.isBefore(start) && !target.isAfter(now);
    }
    if (_reminderHistoryPeriodFilter == '30d') {
      final start = now.subtract(const Duration(days: 29));
      return !target.isBefore(start) && !target.isAfter(now);
    }
    return true;
  }

  String _reminderPeriodLabel(String value) {
    switch (value) {
      case 'today':
        return 'Aujourd\'hui';
      case '7d':
        return '7 jours';
      case '30d':
        return '30 jours';
      case 'all':
      default:
        return 'Tout';
    }
  }

  Map<String, List<_LateFeeAlert>> _groupLateAlertsByClass(List<_LateFeeAlert> alerts) {
    final grouped = <String, List<_LateFeeAlert>>{};
    for (final alert in alerts) {
      grouped.putIfAbsent(alert.className, () => <_LateFeeAlert>[]).add(alert);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    final sorted = <String, List<_LateFeeAlert>>{};
    for (final key in sortedKeys) {
      final rows = grouped[key]!;
      rows.sort((a, b) {
        final byDays = b.daysLate.compareTo(a.daysLate);
        if (byDays != 0) {
          return byDays;
        }
        return b.balance.compareTo(a.balance);
      });
      sorted[key] = rows;
    }
    return sorted;
  }

  String _buildClassRemindersCsv(Map<String, List<_LateFeeAlert>> groupedAlerts) {
    final buffer = StringBuffer();
    buffer.writeln('classe,nb_alertes,montant_total,message_relance');
    groupedAlerts.forEach((className, alerts) {
      final total = alerts.fold<double>(0, (sum, row) => sum + row.balance);
      final message = _buildClassReminderMessage(className: className, alerts: alerts);
      buffer.writeln(
        [
          _csvEscape(className),
          _csvEscape(alerts.length.toString()),
          _csvEscape(total.toStringAsFixed(0)),
          _csvEscape(message),
        ].join(','),
      );
    });
    return buffer.toString();
  }

  Future<void> _copyGlobalReminders(Map<String, List<_LateFeeAlert>> groupedAlerts) async {
    final blocks = <String>[];
    var totalItems = 0;
    var totalAmount = 0.0;
    groupedAlerts.forEach((className, alerts) {
      blocks.add(_buildClassReminderMessage(className: className, alerts: alerts));
      totalItems += alerts.length;
      totalAmount += alerts.fold<double>(0, (sum, row) => sum + row.balance);
    });

    final message = blocks.join('\n\n------------------------------\n\n');
    await Clipboard.setData(ClipboardData(text: message));
    _recordReminderHistory(
      action: 'Relance globale',
      scope: '${groupedAlerts.length} classes',
      itemCount: totalItems,
      totalAmount: totalAmount,
    );
    _showMessage(
      'Relance globale copiée (${groupedAlerts.length} classe(s)).',
      isSuccess: true,
    );
  }

  void _selectLateAlertFee({
    required _LateFeeAlert alert,
    required List<StudentFeeItem> outstandingFees,
  }) {
    final index = outstandingFees.indexWhere((fee) => fee.id == alert.feeId);
    if (index < 0) {
      return;
    }

    final targetPage = (index ~/ _outstandingPageSize) + 1;
    majEtat(() {
      _selectedOutstandingFeeIds.add(alert.feeId);
      _outstandingExpanded = true;
      _outstandingPage = targetPage;
    });
  }
}
