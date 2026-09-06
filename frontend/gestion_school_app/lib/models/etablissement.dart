import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/etablissement_api.dart';
import '../core/network/api_client.dart';
import '../core/network/paged_response.dart';
import '../core/network/token_storage.dart';

final etablissementProvider = ChangeNotifierProvider<EtablissementProvider>(
  (ref) => EtablissementProvider(
    ref.read(tokenStorageProvider),
    ref.read(dioProvider),
  ),
);

// Changes once per app run to invalidate stale browser-cached logo URLs.
int _logoCacheBustToken = DateTime.now().millisecondsSinceEpoch;

void _refreshLogoCacheBustToken() {
  _logoCacheBustToken = DateTime.now().millisecondsSinceEpoch;
}

class Etablissement {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoUrl;

  /// Photo de l'ecole, affichee en fond de l'ecran de connexion.
  ///
  /// Distincte du logo, qui est un dessin cadre serre sur fond blanc: on ne
  /// peut pas l'etaler en pleine page. Facultative -- sans elle, l'ecran de
  /// connexion garde son fond dessine.
  final String? coverUrl;
  final String? stampImageUrl;
  final String? principalSignatureImageUrl;
  final String? cashierSignatureImageUrl;
  final String? principalSignatureLabel;
  final String? cashierSignatureLabel;
  final String? parentSignatureLabel;
  final String? principalSignaturePosition;
  final String? stampPosition;
  final int? principalSignatureScale;
  final int? stampScale;

  Etablissement({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.logoUrl,
    this.coverUrl,
    this.stampImageUrl,
    this.principalSignatureImageUrl,
    this.cashierSignatureImageUrl,
    this.principalSignatureLabel,
    this.cashierSignatureLabel,
    this.parentSignatureLabel,
    this.principalSignaturePosition,
    this.stampPosition,
    this.principalSignatureScale,
    this.stampScale,
  });

  factory Etablissement.fromJson(Map<String, dynamic> json) {
    return Etablissement(
      id: (json['id'] as num).toInt(),
      name: json['name'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      logoUrl: json['logo'],
      coverUrl: json['cover_image'],
      stampImageUrl: json['stamp_image'],
      principalSignatureImageUrl: json['principal_signature_image'],
      cashierSignatureImageUrl: json['cashier_signature_image'],
      principalSignatureLabel: json['principal_signature_label'],
      cashierSignatureLabel: json['cashier_signature_label'],
      parentSignatureLabel: json['parent_signature_label'],
      principalSignaturePosition: json['principal_signature_position'],
      stampPosition: json['stamp_position'],
      principalSignatureScale: (json['principal_signature_scale'] as num?)
          ?.toInt(),
      stampScale: (json['stamp_scale'] as num?)?.toInt(),
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
      'cover_image': coverUrl,
      'stamp_image': stampImageUrl,
      'principal_signature_image': principalSignatureImageUrl,
      'cashier_signature_image': cashierSignatureImageUrl,
      'principal_signature_label': principalSignatureLabel,
      'cashier_signature_label': cashierSignatureLabel,
      'parent_signature_label': parentSignatureLabel,
      'principal_signature_position': principalSignaturePosition,
      'stamp_position': stampPosition,
      'principal_signature_scale': principalSignatureScale,
      'stamp_scale': stampScale,
    };
  }

  String? _cacheBustedAsset(String? raw) {
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

  String? get logoUrlForDisplay {
    return _cacheBustedAsset(logoUrl);
  }

  String? get coverUrlForDisplay => _cacheBustedAsset(coverUrl);

  String? get stampImageUrlForDisplay => _cacheBustedAsset(stampImageUrl);

  String? get principalSignatureImageUrlForDisplay =>
      _cacheBustedAsset(principalSignatureImageUrl);

  String? get cashierSignatureImageUrlForDisplay =>
      _cacheBustedAsset(cashierSignatureImageUrl);
}

class EtablissementProvider extends ChangeNotifier {
  EtablissementProvider(this._tokenStorage, this._dio);

  final TokenStorage _tokenStorage;
  final Dio _dio;
  Etablissement? _selected;
  List<Etablissement> _etablissements = [];
  bool _hydrated = false;
  Future<void>? _chargementEnCours;

  Etablissement? get selected => _selected;
  List<Etablissement> get etablissements => _etablissements;
  bool get hydrated => _hydrated;

  /// Charge la liste depuis l'API, une fois pour toute l'application.
  ///
  /// Deux ecrans la demandaient chacun de son cote, avec deux gestions
  /// d'erreur differentes: l'un affichait la raison de l'echec et proposait
  /// de reessayer, l'autre l'avalait en silence et posait un verrou qu'il ne
  /// relachait jamais. Le meme serveur momentanement absent laissait donc
  /// l'un des deux ecrans utilisable et figeait l'autre.
  ///
  /// [forcer] relance l'appel meme si la liste est deja garnie: c'est ce que
  /// fait le bouton « Reessayer ».
  Future<void> charger({bool forcer = false}) {
    if (!forcer && _etablissements.isNotEmpty) {
      return Future.value();
    }
    // Deux ecrans montes en meme temps ne doivent pas lancer deux appels:
    // le second attend le premier.
    final enCours = _chargementEnCours;
    if (enCours != null) {
      return enCours;
    }

    final futur = _charger();
    _chargementEnCours = futur;
    return futur.whenComplete(() => _chargementEnCours = null);
  }

  Future<void> _charger() async {
    final reponse = await _dio.get(EtablissementApi.etablissements);
    final data = rowsOf(reponse.data).map(Etablissement.fromJson).toList();
    setEtablissements(data);
  }

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
    _refreshLogoCacheBustToken();
    if (_selected != null) {
      for (final etablissement in deduped) {
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
        _refreshLogoCacheBustToken();
      } catch (_) {
        _selected = null;
      }
    }
    _hydrated = true;
    notifyListeners();
  }

  Future<void> selectEtablissement(Etablissement etab) async {
    _selected = etab;
    _refreshLogoCacheBustToken();
    await _tokenStorage.saveSelectedEtablissement(jsonEncode(etab.toJson()));
    notifyListeners();
  }

  Future<void> clearSelection() async {
    _selected = null;
    _refreshLogoCacheBustToken();
    await _tokenStorage.clearSelectedEtablissement();
    notifyListeners();
  }
}
