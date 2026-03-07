import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  final _supplierNameController = TextEditingController();
  final _supplierPhoneController = TextEditingController();
  final _supplierEmailController = TextEditingController();

  final _itemNameController = TextEditingController();
  final _itemQtyController = TextEditingController(text: '0');
  final _itemMinController = TextEditingController(text: '5');
  final _itemUnitController = TextEditingController(text: 'pcs');
  int? _selectedSupplier;

  int? _selectedMovementItem;
  String _movementType = 'in';
  final _movementQtyController = TextEditingController(text: '1');
  final _movementReasonController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _movements = [];
  List<Map<String, dynamic>> _lowStock = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _supplierNameController.dispose();
    _supplierPhoneController.dispose();
    _supplierEmailController.dispose();
    _itemNameController.dispose();
    _itemQtyController.dispose();
    _itemMinController.dispose();
    _itemUnitController.dispose();
    _movementQtyController.dispose();
    _movementReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/suppliers/'),
        dio.get('/stock-items/'),
        dio.get('/stock-movements/'),
        dio.get('/stock-items/low_stock/'),
      ]);

      if (!mounted) return;

      setState(() {
        _suppliers = _extractRows(results[0].data);
        _items = _extractRows(results[1].data);
        _movements = _extractRows(results[2].data);
        _lowStock = _extractRows(results[3].data);

        _selectedSupplier ??= _suppliers.isNotEmpty
            ? _asInt(_suppliers.first['id'])
            : null;
        _selectedMovementItem ??= _items.isNotEmpty
            ? _asInt(_items.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement stock: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _post(
    String endpoint,
    Map<String, dynamic> data,
    String success,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(endpoint, data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final supplierById = {for (final s in _suppliers) _asInt(s['id']): s};
    final itemById = {for (final i in _items) _asInt(i['id']): i};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Stock & Fournitures',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Suivi des fournisseurs, produits, mouvements et alertes stock bas.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Créer fournisseur',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _supplierNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom fournisseur',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _supplierPhoneController,
                  decoration: const InputDecoration(labelText: 'Téléphone'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _supplierEmailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _post('/suppliers/', {
                          'name': _supplierNameController.text.trim(),
                          'phone': _supplierPhoneController.text.trim(),
                          'email': _supplierEmailController.text.trim(),
                        }, 'Fournisseur créé'),
                  child: const Text('Ajouter fournisseur'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Créer article stock',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _itemNameController,
                  decoration: const InputDecoration(labelText: 'Nom article'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _itemQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantité initiale',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _itemMinController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Seuil minimum'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _itemUnitController,
                  decoration: const InputDecoration(
                    labelText: 'Unité (pcs, kg...)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: _selectedSupplier,
                  decoration: const InputDecoration(
                    labelText: 'Fournisseur (optionnel)',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Aucun fournisseur'),
                    ),
                    ..._suppliers.map(
                      (s) => DropdownMenuItem<int?>(
                        value: _asInt(s['id']),
                        child: Text('${s['name']}'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedSupplier = v),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () => _post('/stock-items/', {
                          'name': _itemNameController.text.trim(),
                          'quantity':
                              int.tryParse(_itemQtyController.text.trim()) ?? 0,
                          'minimum_threshold':
                              int.tryParse(_itemMinController.text.trim()) ?? 5,
                          'unit': _itemUnitController.text.trim().isEmpty
                              ? 'pcs'
                              : _itemUnitController.text.trim(),
                          'supplier': _selectedSupplier,
                        }, 'Article stock créé'),
                  child: const Text('Ajouter article'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mouvement de stock',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedMovementItem,
                  decoration: const InputDecoration(labelText: 'Article'),
                  items: _items
                      .map(
                        (i) => DropdownMenuItem<int>(
                          value: _asInt(i['id']),
                          child: Text(
                            '${i['name']} (${i['quantity']} ${i['unit']})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedMovementItem = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _movementType,
                  decoration: const InputDecoration(
                    labelText: 'Type mouvement',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'in', child: Text('Entrée')),
                    DropdownMenuItem(value: 'out', child: Text('Sortie')),
                  ],
                  onChanged: (v) => setState(() => _movementType = v ?? 'in'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _movementQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantité'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _movementReasonController,
                  decoration: const InputDecoration(labelText: 'Raison'),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () => _post('/stock-movements/', {
                          'item': _selectedMovementItem,
                          'movement_type': _movementType,
                          'quantity':
                              int.tryParse(
                                _movementQtyController.text.trim(),
                              ) ??
                              1,
                          'reason': _movementReasonController.text.trim(),
                        }, 'Mouvement enregistré'),
                  child: const Text('Enregistrer mouvement'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Alertes stock bas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_lowStock.isEmpty)
                  const Text('Aucune alerte stock bas')
                else
                  ..._lowStock.map(
                    (i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.warning_amber_rounded),
                      title: Text('${i['name']}'),
                      subtitle: Text(
                        'Stock: ${i['quantity']} ${i['unit']} • Seuil: ${i['minimum_threshold']}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Articles & mouvements',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Fournisseurs: ${_suppliers.length}'),
                Text('Articles: ${_items.length}'),
                Text('Mouvements: ${_movements.length}'),
                const SizedBox(height: 8),
                ..._items
                    .take(20)
                    .map(
                      (i) => Card(
                        child: ListTile(
                          title: Text('${i['name']}'),
                          subtitle: Text(
                            'Fournisseur: ${supplierById[_asInt(i['supplier'])]?['name'] ?? '-'}',
                          ),
                          trailing: Text('${i['quantity']} ${i['unit']}'),
                        ),
                      ),
                    ),
                if (_movements.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Derniers mouvements',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  ..._movements
                      .take(20)
                      .map(
                        (m) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${itemById[_asInt(m['item'])]?['name'] ?? 'Article'} • ${m['movement_type'] == 'in' ? 'Entrée' : 'Sortie'}',
                          ),
                          subtitle: Text(
                            'Qté: ${m['quantity']} • ${m['reason'] ?? ''}',
                          ),
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
      ],
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
}
