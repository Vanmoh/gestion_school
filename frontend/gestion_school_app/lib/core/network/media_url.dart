/// Adresse absolue d'un fichier televerse (photo, justificatif, tampon).
///
/// Le serveur renvoie tantot une URL complete -- c'est le cas du stockage
/// objet, qui signe ses liens -- tantot un chemin relatif quand les fichiers
/// sont servis par l'API elle-meme. Resoudre le second contre l'URL de base
/// est le seul moyen d'obtenir une adresse chargeable dans les deux cas.
///
/// Rendue partageable parce que la liste des eleves et le dossier consulte
/// affichent les memes photos: deux copies de cette regle auraient fini par
/// diverger.
String resolveMediaUrl(String value, String baseUrl) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '';
  if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
    return normalized;
  }

  final base = baseUrl.trim();
  if (base.isEmpty) return normalized;

  try {
    return Uri.parse(base).resolve(normalized).toString();
  } catch (_) {
    // Une base illisible ne doit pas faire disparaitre le chemin: mieux vaut
    // tenter de le charger tel quel que rendre une chaine vide.
    return normalized;
  }
}
