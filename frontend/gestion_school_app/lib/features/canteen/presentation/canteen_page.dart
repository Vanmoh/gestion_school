import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class CanteenPage extends ConsumerStatefulWidget {
  const CanteenPage({super.key});

  @override
  ConsumerState<CanteenPage> createState() => _CanteenPageState();
}

class _CanteenPageState extends ConsumerState<CanteenPage> {
  final _menuNameController = TextEditingController();
  final _menuDescriptionController = TextEditingController();
  final _menuPriceController = TextEditingController(text: '1200');
  DateTime _menuDate = DateTime.now();

  int? _selectedSubStudent;
  int? _selectedSubYear;
  DateTime _subStartDate = DateTime.now();
  DateTime? _subEndDate;
  final _subDailyLimitController = TextEditingController(text: '1');
  String _subStatus = 'active';

  int? _selectedServiceStudent;
  int? _selectedServiceMenu;
  DateTime _serviceDate = DateTime.now();
  final _serviceQtyController = TextEditingController(text: '1');
  bool _servicePaid = false;
  final _serviceNotesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _menus = [];
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _services = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _menuNameController.dispose();
    _menuDescriptionController.dispose();
    _menuPriceController.dispose();
    _subDailyLimitController.dispose();
    _serviceQtyController.dispose();
    _serviceNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/students/'),
        dio.get('/academic-years/'),
        dio.get('/canteen-menus/'),
        dio.get('/canteen-subscriptions/'),
        dio.get('/canteen-services/'),
      ]);

      if (!mounted) return;
      final students = _extractRows(results[0].data);
      final years = _extractRows(results[1].data);
      final menus = _extractRows(results[2].data);
      final subscriptions = _extractRows(results[3].data);
      final services = _extractRows(results[4].data);

      setState(() {
        _students = students;
        _years = years;
        _menus = menus;
        _subscriptions = subscriptions;
        _services = services;

        _selectedSubStudent ??= students.isNotEmpty
            ? _asInt(students.first['id'])
            : null;
        _selectedSubYear ??= years.isNotEmpty
            ? _asInt(years.first['id'])
            : null;
        _selectedServiceStudent ??= students.isNotEmpty
            ? _asInt(students.first['id'])
            : null;
        _selectedServiceMenu ??= menus.isNotEmpty
            ? _asInt(menus.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur chargement cantine: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post(
    String endpoint,
    Map<String, dynamic> data,
    String successMessage,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(endpoint, data: data);
      if (!mounted) return;
      _showMessage(successMessage, isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

<<<<<<< HEAD
=======
  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    const successColor = Color(0xFF197A43);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? successColor : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

>>>>>>> main
  Future<void> _refreshCanteen() async {
    await _loadData();
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
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
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return RefreshIndicator(
        onRefresh: _refreshCanteen,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: const [
            SizedBox(
              height: 460,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final studentById = {for (final s in _students) _asInt(s['id']): s};
    final menuById = {for (final m in _menus) _asInt(m['id']): m};

    final paidServices = _services
        .where((row) => row['is_paid'] == true)
        .length;
    final activeSubscriptions = _subscriptions
        .where((row) => row['status']?.toString() == 'active')
        .length;

    final menuPanel = _sectionCard(
      title: 'Creer un menu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date du menu'),
            subtitle: Text(_apiDate(_menuDate)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _menuDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _menuDate = picked);
            },
          ),
          TextField(
            controller: _menuNameController,
            decoration: const InputDecoration(labelText: 'Nom menu'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _menuDescriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _menuPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Prix unitaire'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving
                ? null
                : () => _post('/canteen-menus/', {
                    'menu_date': _apiDate(_menuDate),
                    'name': _menuNameController.text.trim(),
                    'description': _menuDescriptionController.text.trim(),
                    'unit_price':
                        double.tryParse(_menuPriceController.text.trim()) ?? 0,
                    'is_active': true,
                  }, 'Menu cantine cree'),
            child: const Text('Ajouter menu'),
          ),
        ],
      ),
    );

    final subscriptionPanel = _sectionCard(
      title: 'Abonnement cantine',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _selectedSubStudent,
            decoration: const InputDecoration(labelText: 'Eleve'),
            items: _students
                .map(
                  (row) => DropdownMenuItem<int>(
                    value: _asInt(row['id']),
                    child: Text(_studentLabel(row)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedSubStudent = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _selectedSubYear,
            decoration: const InputDecoration(labelText: 'Annee academique'),
            items: _years
                .map(
                  (row) => DropdownMenuItem<int>(
                    value: _asInt(row['id']),
                    child: Text(_yearLabel(row)),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedSubYear = value),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date debut'),
            subtitle: Text(_apiDate(_subStartDate)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _subStartDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _subStartDate = picked);
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: _subStatus,
            decoration: const InputDecoration(labelText: 'Statut'),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('Actif')),
              DropdownMenuItem(value: 'suspended', child: Text('Suspendu')),
              DropdownMenuItem(value: 'ended', child: Text('Termine')),
            ],
            onChanged: (value) =>
                setState(() => _subStatus = value ?? 'active'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subDailyLimitController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Limite repas / jour'),
          ),
          const SizedBox(height: 10),
          FilledButton.tonal(
            onPressed: _saving
                ? null
                : () => _post('/canteen-subscriptions/', {
                    'student': _selectedSubStudent,
                    'academic_year': _selectedSubYear,
                    'start_date': _apiDate(_subStartDate),
                    'end_date': _subEndDate == null
                        ? null
                        : _apiDate(_subEndDate!),
                    'daily_limit':
                        int.tryParse(_subDailyLimitController.text.trim()) ?? 1,
                    'status': _subStatus,
                  }, 'Abonnement cantine cree'),
            child: const Text('Creer abonnement'),
          ),
        ],
      ),
    );

    final servicePanel = _sectionCard(
      title: 'Service journalier',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            initialValue: _selectedServiceStudent,
            decoration: const InputDecoration(labelText: 'Eleve'),
            items: _students
                .map(
                  (row) => DropdownMenuItem<int>(
                    value: _asInt(row['id']),
                    child: Text(_studentLabel(row)),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _selectedServiceStudent = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _selectedServiceMenu,
            decoration: const InputDecoration(labelText: 'Menu'),
            items: _menus
                .map(
                  (row) => DropdownMenuItem<int>(
                    value: _asInt(row['id']),
                    child: Text('${row['menu_date']} • ${row['name']}'),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedServiceMenu = value),
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date service'),
            subtitle: Text(_apiDate(_serviceDate)),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _serviceDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _serviceDate = picked);
            },
          ),
          TextField(
            controller: _serviceQtyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantite'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _serviceNotesController,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _servicePaid,
            title: const Text('Repas paye'),
            onChanged: (value) => setState(() => _servicePaid = value),
          ),
          FilledButton.tonal(
            onPressed: _saving
                ? null
                : () => _post('/canteen-services/', {
                    'student': _selectedServiceStudent,
                    'menu': _selectedServiceMenu,
                    'served_on': _apiDate(_serviceDate),
                    'quantity':
                        int.tryParse(_serviceQtyController.text.trim()) ?? 1,
                    'is_paid': _servicePaid,
                    'notes': _serviceNotesController.text.trim(),
                  }, 'Service cantine enregistre'),
            child: const Text('Enregistrer service'),
          ),
        ],
      ),
    );

    final followupPanel = _sectionCard(
      title: 'Suivi cantine',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Menus: ${_menus.length}'),
          Text('Abonnements: ${_subscriptions.length}'),
          Text('Services: ${_services.length}'),
          const SizedBox(height: 8),
          ..._services.take(30).map((row) {
            final student = studentById[_asInt(row['student'])];
            final menu = menuById[_asInt(row['menu'])];
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restaurant_menu_outlined),
              title: Text(
                '${_studentLabel(student ?? {})} • ${menu?['name'] ?? '-'}',
              ),
              subtitle: Text(
                '${row['served_on']} • Qte ${row['quantity']} • ${row['is_paid'] == true ? 'Paye' : 'Non paye'}',
              ),
            );
          }),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: _refreshCanteen,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cantine',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Menus, abonnements eleves et services quotidiens.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _loadData,
                icon: const Icon(Icons.sync),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          if (_saving) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metricChip('Eleves', '${_students.length}'),
                _metricChip('Menus', '${_menus.length}'),
                _metricChip('Abonnements', '${_subscriptions.length}'),
                _metricChip('Abonnements actifs', '$activeSubscriptions'),
                _metricChip('Services', '${_services.length}'),
                _metricChip('Services payes', '$paidServices'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1120;
              final leftPanel = Column(
                children: [
                  menuPanel,
                  const SizedBox(height: 12),
                  subscriptionPanel,
                  const SizedBox(height: 12),
                  servicePanel,
                ],
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: leftPanel),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: followupPanel),
                  ],
                );
              }

              return Column(
                children: [
                  leftPanel,
                  const SizedBox(height: 12),
                  followupPanel,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final List<dynamic> rows;
    if (data is Map<String, dynamic> && data['results'] is List) {
      rows = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      rows = data;
    } else {
      rows = [];
    }

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _studentLabel(Map<String, dynamic> row) {
    final matricule = row['matricule']?.toString() ?? 'N/A';
    final fullName = row['user_full_name']?.toString() ?? '';
    final label = fullName.isEmpty ? 'Élève ${row['id'] ?? ''}' : fullName;
    return '$matricule • $label';
  }

  String _yearLabel(Map<String, dynamic> row) {
    final name = row['name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    final start = row['start_date']?.toString() ?? '';
    final end = row['end_date']?.toString() ?? '';
    return '$start - $end';
  }

  String _apiDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
