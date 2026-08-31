/// Qui est en ligne, et depuis quand on ne l'a plus vu.
///
/// Le serveur envoie deux choses: un booleen `online` calcule au moment de la
/// reponse, et l'horodatage `last_seen_at` de la derniere activite. L'ecran ne
/// peut pas se contenter du booleen: il est vrai a la seconde ou il arrive et
/// le reste ensuite indefiniment, meme quand la personne a ferme sa fenetre
/// depuis dix minutes. C'est ce qui faisait rester « en ligne » des comptes
/// partis depuis des jours.
///
/// On garde donc l'horodatage et on relit la meme regle que le serveur, ici,
/// a chaque affichage.
library;

/// La meme fenetre que `apps.common.presence.FENETRE_PRESENCE` cote serveur.
/// Les deux doivent bouger ensemble: un client plus tolerant que le serveur
/// afficherait « en ligne » sur quelqu'un que le serveur donne parti.
const Duration fenetrePresence = Duration(seconds: 75);

/// L'etat de presence d'une personne, tel qu'un ecran l'affiche.
class Presence {
  /// Le dernier signe de vie connu. `null` quand on ne l'a jamais vue.
  final DateTime? vuA;

  /// Ce que le serveur disait quand il a repondu, garde pour le cas ou il
  /// n'aurait pas envoye d'horodatage (serveur anterieur).
  final bool _annonceEnLigne;

  const Presence({this.vuA, bool annonceEnLigne = false})
    : _annonceEnLigne = annonceEnLigne;

  /// Lit une charge `{online, last_seen_at}` — annuaire, snapshot websocket ou
  /// fiche d'un compte, la forme est la meme partout.
  factory Presence.depuisJson(Map<String, dynamic> json) {
    return Presence(
      vuA: DateTime.tryParse(json['last_seen_at']?.toString() ?? '')?.toLocal(),
      annonceEnLigne: json['online'] == true,
    );
  }

  /// Jamais vue: ni socket, ni la moindre requete depuis la creation du compte.
  bool get jamaisVue => vuA == null;

  bool enLigne({DateTime? maintenant}) {
    final quand = vuA;
    // Sans horodatage, il ne reste que la parole du serveur. Elle vieillit,
    // mais l'afficher hors ligne a tort serait pire.
    if (quand == null) return _annonceEnLigne;
    final ecart = (maintenant ?? DateTime.now()).difference(quand);
    // Horloge du poste en avance sur celle du serveur: un horodatage « dans le
    // futur » reste un signe de vie, pas une absence.
    if (ecart.isNegative) return true;
    return ecart <= fenetrePresence;
  }

  /// « En ligne », « Vu aujourd'hui à 14:32 », « Jamais connecté ».
  String libelle({
    DateTime? maintenant,
    String repliJamaisVu = 'Jamais connecté',
  }) {
    if (enLigne(maintenant: maintenant)) return 'En ligne';
    final quand = vuA;
    if (quand == null) return repliJamaisVu;
    return 'Vu ${dateHeureLisible(quand, maintenant: maintenant)}';
  }
}

/// « aujourd'hui à 14:32 », « hier à 08:05 », « le 31/08/2026 à 14:32 ».
///
/// La date seule ne suffisait pas: entre deux visites du meme jour, savoir
/// laquelle est la plus recente demande l'heure et la minute.
String dateHeureLisible(DateTime valeur, {DateTime? maintenant}) {
  final local = valeur.toLocal();
  final reference = (maintenant ?? DateTime.now()).toLocal();
  final heure =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

  final jourDeLaValeur = DateTime(local.year, local.month, local.day);
  final aujourdHui = DateTime(reference.year, reference.month, reference.day);
  final ecartEnJours = aujourdHui.difference(jourDeLaValeur).inDays;

  if (ecartEnJours == 0) return 'aujourd’hui à $heure';
  if (ecartEnJours == 1) return 'hier à $heure';

  final jour = local.day.toString().padLeft(2, '0');
  final mois = local.month.toString().padLeft(2, '0');
  return 'le $jour/$mois/${local.year} à $heure';
}
