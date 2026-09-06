import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/web/memoire_demarrage.dart';
import '../data/personnalisation_repository.dart';
import '../domain/personnalisation.dart';

final personnalisationRepositoryProvider = Provider<PersonnalisationRepository>(
  (ref) => PersonnalisationRepository(ref.read(dioProvider)),
);

/// L'identité de l'école, partagée par toute l'application.
///
/// Un `ChangeNotifier` et non un `FutureProvider` : l'écran de connexion, le
/// portail et l'écran de réglages lisent tous la même identité, et une
/// modification faite dans les réglages doit se voir partout sans qu'on
/// recharge l'application.
final personnalisationProvider =
    ChangeNotifierProvider<PersonnalisationController>((ref) {
      return PersonnalisationController(
        ref.read(personnalisationRepositoryProvider),
      );
    });

class PersonnalisationController extends ChangeNotifier {
  final PersonnalisationRepository _repository;

  PersonnalisationController(this._repository);

  /// L'identité par défaut tant que le serveur n'a pas répondu.
  ///
  /// Jamais nulle : les écrans s'affichent avant le premier chargement, et
  /// les faire attendre montrerait une page blanche là où il suffit de
  /// remplacer un nom quelques instants plus tard.
  Personnalisation _valeur = const Personnalisation();
  Personnalisation get valeur => _valeur;

  bool _chargement = false;
  bool get chargement => _chargement;

  bool _chargee = false;

  String? _erreur;
  String? get erreur => _erreur;

  /// Charge l'identité depuis le serveur.
  ///
  /// [forcer] rejoue l'appel même si elle est déjà connue : sans lui, la
  /// première réponse vaudrait pour toute la session, et une modification
  /// faite ailleurs ne se verrait jamais.
  Future<void> charger({bool forcer = false}) async {
    if (_chargee && !forcer) return;
    if (_chargement) return;

    _chargement = true;
    _erreur = null;
    notifyListeners();

    try {
      _valeur = await _repository.charger();
      _chargee = true;
      // L'ecran de demarrage HTML s'affiche avant Flutter et ne peut donc rien
      // demander au serveur. On lui laisse l'identite de l'ecole pour la
      // prochaine ouverture; sans elle il garde ses libelles d'origine.
      memoriserLaMarque(
        nomEcole: _valeur.nomEcole,
        nomApplication: _valeur.nomApplication,
        logoUrl: _valeur.logoUrl,
        imageFondUrl: _valeur.imageFondUrl,
        couleur: _valeur.couleurPrincipale,
      );
    } catch (_) {
      // L'application doit rester utilisable sans son identité: mieux vaut
      // les libellés d'origine qu'un écran de connexion en erreur.
      _erreur = 'Personnalisation indisponible.';
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }

  /// Enregistre et diffuse la nouvelle identité.
  Future<void> enregistrer(
    Map<String, dynamic> champs, {
    Uint8List? logo,
    String? nomDuLogo,
    Uint8List? imageFond,
    String? nomDeLImageFond,
  }) async {
    _valeur = await _repository.enregistrer(
      champs,
      logo: logo,
      nomDuLogo: nomDuLogo,
      imageFond: imageFond,
      nomDeLImageFond: nomDeLImageFond,
    );
    _chargee = true;
    notifyListeners();
  }
}
