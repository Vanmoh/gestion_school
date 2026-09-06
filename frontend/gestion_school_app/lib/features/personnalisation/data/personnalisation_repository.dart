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
  /// [logo] et [imageFond] remplacent l'image correspondante ; les laisser
  /// nuls garde celle en place — on ne veut pas qu'un simple changement de
  /// téléphone efface le logo ou la photo de fond.
  Future<Personnalisation> enregistrer(
    Map<String, dynamic> champs, {
    Uint8List? logo,
    String? nomDuLogo,
    Uint8List? imageFond,
    String? nomDeLImageFond,
  }) async {
    final aUnLogo = logo != null && logo.isNotEmpty;
    final aUnFond = imageFond != null && imageFond.isNotEmpty;

    final Object corps;
    if (aUnLogo || aUnFond) {
      corps = FormData.fromMap(<String, dynamic>{
        ...champs,
        if (aUnLogo)
          'logo': MultipartFile.fromBytes(
            logo,
            filename: nomDuLogo ?? 'logo.png',
          ),
        if (aUnFond)
          'image_fond': MultipartFile.fromBytes(
            imageFond,
            filename: nomDeLImageFond ?? 'fond.jpg',
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
