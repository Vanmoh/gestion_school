import 'package:flutter/material.dart';

/// L'identité de l'école, telle que les écrans la portent.
///
/// Tout cela vivait en dur dans `SchoolBranding` : le nom, le logo, le
/// téléphone, jusqu'aux filières listées sur l'écran de connexion. Servir une
/// autre école demandait de recompiler l'application avec ses constantes,
/// autant dire de maintenir une version par client.
///
/// Chaque libellé est facultatif. Vide, l'écran garde sa formulation
/// d'origine : une école qui ne personnalise rien ne doit pas hériter de
/// libellés blancs.
@immutable
class Personnalisation {
  final String nomApplication;
  final String nomEcole;
  final String sigle;
  final String logoUrl;

  final String telephone;
  final String email;
  final String adresse;

  final String titreConnexion;
  final String sousTitreConnexion;
  final String titrePortail;
  final String sousTitrePortail;
  final String messageAccueil;
  final String piedDePage;

  final String couleurPrincipale;

  const Personnalisation({
    this.nomApplication = 'GESTION SCOLAIRE',
    this.nomEcole = '',
    this.sigle = '',
    this.logoUrl = '',
    this.telephone = '',
    this.email = '',
    this.adresse = '',
    this.titreConnexion = '',
    this.sousTitreConnexion = '',
    this.titrePortail = '',
    this.sousTitrePortail = '',
    this.messageAccueil = '',
    this.piedDePage = '',
    this.couleurPrincipale = '#6D5BFF',
  });

  factory Personnalisation.fromJson(Map<String, dynamic> json) {
    String texte(String cle) => (json[cle] ?? '').toString().trim();
    return Personnalisation(
      nomApplication: texte('nom_application').isEmpty
          ? 'GESTION SCOLAIRE'
          : texte('nom_application'),
      nomEcole: texte('nom_ecole'),
      sigle: texte('sigle'),
      logoUrl: texte('logo_url'),
      telephone: texte('telephone'),
      email: texte('email'),
      adresse: texte('adresse'),
      titreConnexion: texte('titre_connexion'),
      sousTitreConnexion: texte('sous_titre_connexion'),
      titrePortail: texte('titre_portail'),
      sousTitrePortail: texte('sous_titre_portail'),
      messageAccueil: texte('message_accueil'),
      piedDePage: texte('pied_de_page'),
      couleurPrincipale: texte('couleur_principale').isEmpty
          ? '#6D5BFF'
          : texte('couleur_principale'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'nom_application': nomApplication,
    'nom_ecole': nomEcole,
    'sigle': sigle,
    'logo_url': logoUrl,
    'telephone': telephone,
    'email': email,
    'adresse': adresse,
    'titre_connexion': titreConnexion,
    'sous_titre_connexion': sousTitreConnexion,
    'titre_portail': titrePortail,
    'sous_titre_portail': sousTitrePortail,
    'message_accueil': messageAccueil,
    'pied_de_page': piedDePage,
    'couleur_principale': couleurPrincipale,
  };

  /// La couleur d'accent, ou celle par défaut si la valeur est illisible.
  ///
  /// Le serveur la valide déjà, mais une réponse d'un autre âge — ou une
  /// personnalisation restaurée d'une sauvegarde — pourrait en porter une
  /// mauvaise, et une exception ici emporterait le démarrage de
  /// l'application entière.
  Color get couleur {
    final brut = couleurPrincipale.replaceAll('#', '').trim();
    if (brut.length != 6) return const Color(0xFF6D5BFF);
    final valeur = int.tryParse(brut, radix: 16);
    if (valeur == null) return const Color(0xFF6D5BFF);
    return Color(0xFF000000 | valeur);
  }

  /// Le nom à afficher quand la place manque : le sigle s'il existe.
  String get nomCourt => sigle.isNotEmpty ? sigle : nomEcole;

  /// Ce que l'écran affiche pour [valeur], ou [defaut] si rien n'est réglé.
  static String ou(String valeur, String defaut) =>
      valeur.trim().isEmpty ? defaut : valeur.trim();

  Personnalisation copyWith({
    String? nomApplication,
    String? nomEcole,
    String? sigle,
    String? logoUrl,
    String? telephone,
    String? email,
    String? adresse,
    String? titreConnexion,
    String? sousTitreConnexion,
    String? titrePortail,
    String? sousTitrePortail,
    String? messageAccueil,
    String? piedDePage,
    String? couleurPrincipale,
  }) {
    return Personnalisation(
      nomApplication: nomApplication ?? this.nomApplication,
      nomEcole: nomEcole ?? this.nomEcole,
      sigle: sigle ?? this.sigle,
      logoUrl: logoUrl ?? this.logoUrl,
      telephone: telephone ?? this.telephone,
      email: email ?? this.email,
      adresse: adresse ?? this.adresse,
      titreConnexion: titreConnexion ?? this.titreConnexion,
      sousTitreConnexion: sousTitreConnexion ?? this.sousTitreConnexion,
      titrePortail: titrePortail ?? this.titrePortail,
      sousTitrePortail: sousTitrePortail ?? this.sousTitrePortail,
      messageAccueil: messageAccueil ?? this.messageAccueil,
      piedDePage: piedDePage ?? this.piedDePage,
      couleurPrincipale: couleurPrincipale ?? this.couleurPrincipale,
    );
  }
}
