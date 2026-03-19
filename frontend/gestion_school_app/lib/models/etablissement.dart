import 'package:flutter_riverpod/flutter_riverpod.dart';
final etablissementProvider = ChangeNotifierProvider<EtablissementProvider>((ref) => EtablissementProvider());
import 'package:flutter/foundation.dart';

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
      id: json['id'],
      name: json['name'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      logoUrl: json['logo'],
    );
  }
}

class EtablissementProvider extends ChangeNotifier {
  Etablissement? _selected;
  List<Etablissement> _etablissements = [];

  Etablissement? get selected => _selected;
  List<Etablissement> get etablissements => _etablissements;

  void setEtablissements(List<Etablissement> etablissements) {
    _etablissements = etablissements;
    notifyListeners();
  }

  void selectEtablissement(Etablissement etab) {
    _selected = etab;
    notifyListeners();
  }

  void clearSelection() {
    _selected = null;
    notifyListeners();
  }
}
