import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminShellNavigationKeyProvider = StateProvider<String?>((ref) => null);

final financeOpenGuidedPaymentIntentProvider = StateProvider<bool>(
	(ref) => false,
);

/// L'enseignant a preselectionner en arrivant dans le module « Émargements ».
///
/// La palette enseignant renvoie vers ce module depuis le detail de
/// l'emargement: sans cette intention, on y arrivait sur le premier enseignant
/// de la liste et il fallait le rechercher de nouveau.
///
/// La page la consomme des qu'elle l'a lue, sinon toute visite ulterieure
/// rouvrirait le meme enseignant.
final teacherTimesheetFocusProvider = StateProvider<int?>((ref) => null);

/// Ouvre le module « Emploi du temps » directement sur la vue par enseignant.
///
/// Ce module n'a pas de selecteur d'un enseignant unique -- il rend la charge
/// de tous -- mais y arriver deja bascule en vue enseignant evite deux clics
/// et place devant le bon tableau.
final timetableTeacherViewIntentProvider = StateProvider<bool>((ref) => false);
