import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/personnalisation.dart';

/// L'accès à l'identité de l'école.
///
/// La lecture ne demande pas d'authentification : les deux écrans qui en ont
/// le plus besoin — la connexion et le portail de sélection — s'affichent
/// avant qu'on soit connecté.
class PersonnalisationRepository {
  static const String _chemin = '/common/personnalisation/';

  final Dio dio;

  PersonnalisationRepository(this.dio);

  Future<Personnalisation> charger() async {
    final reponse = await dio.get(_chemin);
    return Personnalisation.fromJson(
      Map<String, dynamic>.from(reponse.data as Map),
    );
  }

  /// Enregistre les champs fournis. Réservé au super admin, le serveur en
  /// est seul juge.
  ///
  /// [logo] remplace l'image ; le laisser nul garde celle en place — on ne
  /// veut pas qu'un simple changement de téléphone efface le logo.
  Future<Personnalisation> enregistrer(
    Map<String, dynamic> champs, {
    Uint8List? logo,
    String? nomDuLogo,
  }) async {
    final Object corps;
    if (logo != null && logo.isNotEmpty) {
      corps = FormData.fromMap(<String, dynamic>{
        ...champs,
        'logo': MultipartFile.fromBytes(
          logo,
          filename: nomDuLogo ?? 'logo.png',
        ),
      });
    } else {
      corps = champs;
    }

    final reponse = await dio.patch(_chemin, data: corps);
    return Personnalisation.fromJson(
      Map<String, dynamic>.from(reponse.data as Map),
    );
  }
}
