/// L'identité de l'école, réglée depuis l'application au lieu du code.
///
/// Le nom, le logo, le téléphone et jusqu'aux libellés des écrans publics
/// vivaient en dur : servir une autre école demandait de recompiler. Ce qui
/// se vérifie ici est la règle qui rend cela sûr — un réglage absent laisse
/// l'écran d'origine, et une valeur illisible ne fait pas tomber
/// l'application.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/personnalisation/domain/personnalisation.dart';

void main() {
  group('lecture du serveur', () {
    test('une reponse complete se lit entierement', () {
      final p = Personnalisation.fromJson(<String, dynamic>{
        'nom_application': 'GESTION CSOB',
        'nom_ecole': 'Complexe Scolaire Oumar Bah',
        'sigle': 'CSOB',
        'logo_url': 'http://api/media/personnalisation/logo.png',
        'telephone': '66 74 22 32',
        'titre_portail': 'Nos établissements',
        'couleur_principale': '#1A2B3C',
      });

      expect(p.nomApplication, 'GESTION CSOB');
      expect(p.sigle, 'CSOB');
      expect(p.titrePortail, 'Nos établissements');
      expect(p.couleur, const Color(0xFF1A2B3C));
    });

    test('une reponse vide ne laisse pas l_application sans nom', () {
      final p = Personnalisation.fromJson(<String, dynamic>{});

      expect(p.nomApplication, 'GESTION SCOLAIRE');
      expect(p.couleur, const Color(0xFF6D5BFF));
    });

    test('les espaces autour des valeurs sont retires', () {
      final p = Personnalisation.fromJson(<String, dynamic>{
        'nom_ecole': '  École Bilingue  ',
      });

      expect(p.nomEcole, 'École Bilingue');
    });

    test('un nom d_application vide retombe sur le defaut', () {
      // Le titre de l'onglet du navigateur: le laisser vide donnerait une
      // fenêtre sans nom dans la barre des tâches.
      final p = Personnalisation.fromJson(<String, dynamic>{
        'nom_application': '   ',
      });

      expect(p.nomApplication, 'GESTION SCOLAIRE');
    });
  });

  group('la couleur ne fait jamais tomber l_application', () {
    test('une couleur sans diese se lit quand meme', () {
      const p = Personnalisation(couleurPrincipale: '1A2B3C');
      expect(p.couleur, const Color(0xFF1A2B3C));
    });

    test('une couleur illisible retombe sur le defaut', () {
      // Le serveur la valide, mais une sauvegarde restaurée d'un autre âge
      // pourrait en porter une mauvaise — et une exception ici emporterait
      // le démarrage entier.
      const p = Personnalisation(couleurPrincipale: 'bleu ciel');
      expect(p.couleur, const Color(0xFF6D5BFF));
    });

    test('une couleur tronquee retombe sur le defaut', () {
      const p = Personnalisation(couleurPrincipale: '#ABC');
      expect(p.couleur, const Color(0xFF6D5BFF));
    });

    test('la couleur reste opaque', () {
      // Sans le canal alpha force, une couleur sombre rendrait l'interface
      // transparente au lieu de la teinter.
      const p = Personnalisation(couleurPrincipale: '#000000');
      expect(p.couleur, const Color(0xFF000000));
    });
  });

  group('un reglage absent laisse l_ecran d_origine', () {
    test('un libelle vide cede la place au defaut', () {
      expect(Personnalisation.ou('', 'Choisissez votre établissement'),
          'Choisissez votre établissement');
    });

    test('un libelle fait d_espaces compte pour vide', () {
      expect(Personnalisation.ou('   ', 'Repli'), 'Repli');
    });

    test('un libelle rempli prime sur le defaut', () {
      expect(Personnalisation.ou('Nos écoles', 'Repli'), 'Nos écoles');
    });
  });

  group('nom court', () {
    test('le sigle sert quand la place manque', () {
      const p = Personnalisation(nomEcole: 'Lycée Technique Oumar Bah', sigle: 'LTOB');
      expect(p.nomCourt, 'LTOB');
    });

    test('sans sigle, le nom complet reste affiche', () {
      const p = Personnalisation(nomEcole: 'École Bilingue');
      expect(p.nomCourt, 'École Bilingue');
    });
  });

  test('l_aller-retour par json ne perd rien', () {
    const depart = Personnalisation(
      nomApplication: 'GESTION CSOB',
      nomEcole: 'Complexe Scolaire',
      sigle: 'CSOB',
      telephone: '66 00 00 00',
      titreConnexion: 'Bienvenue',
      messageAccueil: 'Choisissez votre site',
      couleurPrincipale: '#112233',
    );

    final retour = Personnalisation.fromJson(depart.toJson());

    expect(retour.nomEcole, depart.nomEcole);
    expect(retour.titreConnexion, depart.titreConnexion);
    expect(retour.messageAccueil, depart.messageAccueil);
    expect(retour.couleur, depart.couleur);
  });
}
