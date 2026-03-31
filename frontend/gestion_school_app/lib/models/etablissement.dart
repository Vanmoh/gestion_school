import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import '../core/network/token_storage.dart';

final etablissementProvider = ChangeNotifierProvider<EtablissementProvider>(
  (ref) => EtablissementProvider(ref.read(tokenStorageProvider)),
);

// Changes once per app run to invalidate stale browser-cached logo URLs.
final int _logoCacheBustToken = DateTime.now().millisecondsSinceEpoch;

class Etablissement {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoUrl;

  Etablissement({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.logoUrl,
  });

  factory Etablissement.fromJson(Map<String, dynamic> json) {
    return Etablissement(
      id: (json['id'] as num).toInt(),
      name: json['name'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      logoUrl: json['logo'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'logo': logoUrl,
    };
  }

  String? get logoUrlForDisplay {
    final raw = logoUrl;
    if (raw == null || raw.isEmpty) {
      return raw;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return raw;
    }
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['v'] = _logoCacheBustToken.toString();
    return uri.replace(queryParameters: queryParams).toString();
  }
}

class EtablissementProvider extends ChangeNotifier {
  EtablissementProvider(this._tokenStorage);

  final TokenStorage _tokenStorage;
  Etablissement? _selected;
  List<Etablissement> _etablissements = [];
  bool _hydrated = false;

  Etablissement? get selected => _selected;
  List<Etablissement> get etablissements => _etablissements;
  bool get hydrated => _hydrated;

  void setEtablissements(List<Etablissement> etablissements) {
    final deduped = <Etablissement>[];
    final seen = <String>{};

    for (final etab in etablissements) {
      final idKey = 'id:${etab.id}';
      final nameKey =
          'name:${etab.name.trim().toLowerCase()}|addr:${(etab.address ?? '').trim().toLowerCase()}';
      if (seen.contains(idKey) || seen.contains(nameKey)) {
        continue;
      }
      seen.add(idKey);
      seen.add(nameKey);
      deduped.add(etab);
    }

    _etablissements = deduped;
    if (_selected != null) {
      for (final etablissement in etablissements) {
        if (etablissement.id == _selected!.id) {
          _selected = etablissement;
          break;
        }
      }
    }
    notifyListeners();
  }

  Future<void> hydrate() async {
    if (_hydrated) {
      return;
    }

    final raw = await _tokenStorage.selectedEtablissement();
    if (raw != null && raw.isNotEmpty) {
      try {
        _selected = Etablissement.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        _selected = null;
      }
    }
    _hydrated = true;
    notifyListeners();
  }

  Future<void> selectEtablissement(Etablissement etab) async {
    _selected = etab;
    await _tokenStorage.saveSelectedEtablissement(jsonEncode(etab.toJson()));
    notifyListeners();
  }

  Future<void> clearSelection() async {
    _selected = null;
    await _tokenStorage.clearSelectedEtablissement();
    notifyListeners();
  }
}
