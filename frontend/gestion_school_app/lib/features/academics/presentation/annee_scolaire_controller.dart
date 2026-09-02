import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/token_storage.dart';
import '../data/annees_scolaires_repository.dart';
import '../domain/annee_scolaire.dart';

final anneesScolairesRepositoryProvider = Provider<AnneesScolairesRepository>((
  ref,
) {
  return AnneesScolairesRepository(ref.read(dioProvider));
});

/// L'année de travail, partagee par toute l'application.
///
/// « Notes », « Examens » et « Academique » avaient chacune son selecteur
/// d'annee, et rien ne les accordait: on pouvait saisir une note sur une
/// annee tout en consultant l'emploi du temps d'une autre. L'annee vit
/// desormais ici, et voyage dans l'en-tete `X-Academic-Year-Id` que pose
/// le client HTTP -- exactement comme l'etablissement.
final anneeScolaireProvider =
    ChangeNotifierProvider<AnneeScolaireController>((ref) {
      return AnneeScolaireController(
        ref.read(tokenStorageProvider),
        ref.read(anneesScolairesRepositoryProvider),
      );
    });

class AnneeScolaireController extends ChangeNotifier {
  AnneeScolaireController(this._tokenStorage, this._repository);

  final TokenStorage _tokenStorage;
  final AnneesScolairesRepository _repository;

  AnneeScolaire? _selectionnee;
  List<AnneeScolaire> _annees = const [];
  bool _hydratee = false;
  bool _chargement = false;
  String? _erreur;

  AnneeScolaire? get selectionnee => _selectionnee;
  List<AnneeScolaire> get annees => _annees;
  bool get hydratee => _hydratee;
  bool get chargement => _chargement;
  String? get erreur => _erreur;

  /// Vrai quand l'année consultee n'accepte plus la saisie ordinaire.
  bool get consulteUneAnneeCloturee => _selectionnee?.estCloturee ?? false;

  /// Relit le choix precedent avant tout appel reseau.
  ///
  /// Sans cela, la premiere requete de l'application partirait sans
  /// en-tete et le serveur repondrait sur l'annee courante, avant que
  /// l'ecran ne bascule sous les yeux de l'utilisateur.
  Future<void> hydrater() async {
    if (_hydratee) return;

    final brut = await _tokenStorage.selectedAcademicYear();
    if (brut != null && brut.isNotEmpty) {
      try {
        _selectionnee = AnneeScolaire.fromJson(
          jsonDecode(brut) as Map<String, dynamic>,
        );
      } catch (_) {
        _selectionnee = null;
      }
    }
    _hydratee = true;
    notifyListeners();
  }

  /// Charge les annees de l'etablissement actif.
  ///
  /// A appeler apres chaque changement d'établissement: les années d'une
  /// ecole n'ont aucun sens dans une autre.
  Future<void> charger() async {
    _chargement = true;
    _erreur = null;
    notifyListeners();

    try {
      final annees = await _repository.fetchAnnees();
      _annees = annees;

      final choisie = _selectionnee;
      final encoreValide =
          choisie != null && annees.any((annee) => annee.id == choisie.id);
      if (!encoreValide) {
        // L'année en cours de l'etablissement, a defaut la plus recente.
        final courante = annees.where((annee) => annee.estCourante).firstOrNull;
        await selectionner(courante ?? annees.firstOrNull);
      } else {
        // Recale le libelle et l'etat de cloture sur ce que dit le serveur.
        _selectionnee = annees.firstWhere((annee) => annee.id == choisie.id);
      }
    } catch (error) {
      _erreur = 'Impossible de charger les années scolaires.';
    } finally {
      _chargement = false;
      notifyListeners();
    }
  }

  Future<void> selectionner(AnneeScolaire? annee) async {
    _selectionnee = annee;
    if (annee == null) {
      await _tokenStorage.clearSelectedAcademicYear();
    } else {
      await _tokenStorage.saveSelectedAcademicYear(jsonEncode(annee.toJson()));
    }
    notifyListeners();
  }

  /// Oublie le choix: a la deconnexion, ou au changement d'ecole.
  Future<void> reinitialiser() async {
    _selectionnee = null;
    _annees = const [];
    _hydratee = false;
    await _tokenStorage.clearSelectedAcademicYear();
    notifyListeners();
  }
}
