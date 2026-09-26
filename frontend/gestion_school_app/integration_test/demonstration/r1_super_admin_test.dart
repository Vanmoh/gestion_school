import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 1 — le super administrateur, celui qui installe l'école.
///
/// Son geste le plus parlant est la personnalisation : on change le nom de
/// l'établissement et sa couleur, et **le titre de la fenêtre change à
/// l'image**. Rien n'est simulé, c'est le thème de l'application qui suit.
///
/// La sauvegarde est montrée sans être franchie : on ouvre l'écran, on désigne
/// le bouton de restauration, et on s'arrête là. Filmer une restauration
/// effacerait la base au milieu du tournage.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre du super administrateur', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'super_admin',
      identifiant: 'superadmin',
      motDePasse: 'Admin@12345',
      gestes: (pilote) async {
        if (await pilote.ouvrirLeModule(
          'personnalisation',
          sousTitre: 'Le nom, le logo et les couleurs de l\'école se règlent ici.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'etablissements',
          sousTitre: 'Une installation peut porter plusieurs écoles.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule(
          'users',
          sousTitre: 'Créer un compte, et remettre son mot de passe provisoire.',
        )) {
          await pilote.appuyerSurLaCle('basculer-creation-utilisateur');
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule(
          'backup_restore',
          sousTitre:
              'La restauration remplace toute la base : on la montre, on ne la lance pas.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'activity_logs',
          sousTitre: 'Qui a agi, sur quel module, et ce que le serveur a répondu.',
        )) {
          await pilote.soulignerLaCle(
            'filtre-auteur',
            texte: '« Qui a fait ça » : la question qu\'on pose à un journal.',
          );
          await pilote.appuyerSurLaCle('filtre-module');
          await pilote.poser(duree: const Duration(seconds: 3));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
