import 'package:dio/dio.dart';

import '../domain/activity_log_models.dart';

/// Le journal d'audit, et les filtres que le serveur sait appliquer.
///
/// L'écran interrogeait Dio depuis son `State`, avec `page_size: 80` écrit en
/// dur — une valeur qui contrariait l'intercepteur de pagination du projet,
/// lequel demande 500 lignes et suit `next`. Et il n'offrait que la méthode
/// HTTP, le succès et les dates, alors que le serveur filtre aussi sur
/// l'auteur, le rôle et le module: les deux questions qu'on pose réellement à
/// un journal d'audit — « qui a fait ça » et « que s'est-il passé dans les
/// paiements » — n'étaient pas posables.
class ActivityLogsRepository {
  final Dio dio;

  ActivityLogsRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return [];
  }

  Map<String, dynamic> parametres(FiltreDuJournal filtre) => filtre.enRequete();

  Future<List<LigneDuJournal>> fetchLignes(
    FiltreDuJournal filtre, {
    CancelToken? annulation,
  }) async {
    final response = await dio.get(
      '/activity-logs/',
      queryParameters: filtre.enRequete(),
      cancelToken: annulation,
    );

    return _extractRows(response.data)
        .map((row) => (row as Map<String, dynamic>))
        .map(
          (row) => LigneDuJournal(
            id: (row['id'] as num?)?.toInt() ?? 0,
            quand: row['created_at']?.toString() ?? '',
            auteur: row['user_display']?.toString() ??
                row['user_username']?.toString() ??
                row['user']?.toString() ??
                '',
            role: row['role']?.toString() ?? '',
            action: row['action']?.toString() ?? '',
            methode: row['method']?.toString() ?? '',
            module: row['module']?.toString() ?? '',
            chemin: row['path']?.toString() ?? '',
            cible: row['target']?.toString() ?? '',
            statutHttp: (row['status_code'] as num?)?.toInt() ?? 0,
            reussi: row['success'] == true,
            adresseIp: row['ip_address']?.toString() ?? '',
            details: row['details']?.toString() ?? '',
            etablissement: row['etablissement_name']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<RepertoireDuJournal> fetchRepertoire() async {
    final response = await dio.get('/activity-logs/repertoire/');
    final data = response.data;
    if (data is! Map<String, dynamic>) return RepertoireDuJournal.vide;

    return RepertoireDuJournal(
      modules: [
        for (final module in (data['modules'] as List<dynamic>? ?? const []))
          module.toString(),
      ],
      auteurs: [
        for (final auteur in (data['auteurs'] as List<dynamic>? ?? const []))
          if (auteur is Map<String, dynamic>)
            AuteurDuJournal(
              id: (auteur['id'] as num?)?.toInt() ?? 0,
              nom: auteur['label']?.toString() ?? '',
              role: auteur['role']?.toString() ?? '',
            ),
      ],
    );
  }

  /// Les exports reprennent exactement les filtres affichés.
  Future<List<int>> exporter({
    required FiltreDuJournal filtre,
    required bool enExcel,
  }) async {
    final response = await dio.get<List<int>>(
      enExcel ? '/activity-logs/export-excel/' : '/activity-logs/export-pdf/',
      queryParameters: filtre.enRequete(),
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  }
}

/// Ce sur quoi le journal se filtre, porté au serveur.
///
/// Une classe à part plutôt que huit paramètres: un `family` prend une seule
/// clé, et elle doit savoir se comparer — sans quoi chaque reconstruction
/// relancerait la requête.
class FiltreDuJournal {
  final String recherche;
  final int? auteurId;
  final String? role;
  final String? module;
  final String? methode;
  final bool? reussi;
  final String? depuis;
  final String? jusqua;
  final TriDuJournal tri;

  const FiltreDuJournal({
    this.recherche = '',
    this.auteurId,
    this.role,
    this.module,
    this.methode,
    this.reussi,
    this.depuis,
    this.jusqua,
    this.tri = TriDuJournal.plusRecentDAbord,
  });

  static const aucun = FiltreDuJournal();

  bool get estVide =>
      recherche.trim().isEmpty &&
      auteurId == null &&
      role == null &&
      module == null &&
      methode == null &&
      reussi == null &&
      depuis == null &&
      jusqua == null &&
      tri == TriDuJournal.plusRecentDAbord;

  Map<String, dynamic> enRequete() => {
    if (recherche.trim().isNotEmpty) 'search': recherche.trim(),
    'user': ?auteurId,
    'role': ?role,
    'module': ?module,
    'method': ?methode,
    'success': ?reussi,
    'date_from': ?depuis,
    'date_to': ?jusqua,
    'ordering': tri.code,
  };

  FiltreDuJournal avec({
    String? recherche,
    int? auteurId,
    String? role,
    String? module,
    String? methode,
    bool? reussi,
    String? depuis,
    String? jusqua,
    TriDuJournal? tri,
    bool viderAuteur = false,
    bool viderRole = false,
    bool viderModule = false,
    bool viderMethode = false,
    bool viderReussite = false,
    bool viderDepuis = false,
    bool viderJusqua = false,
  }) {
    return FiltreDuJournal(
      recherche: recherche ?? this.recherche,
      auteurId: viderAuteur ? null : (auteurId ?? this.auteurId),
      role: viderRole ? null : (role ?? this.role),
      module: viderModule ? null : (module ?? this.module),
      methode: viderMethode ? null : (methode ?? this.methode),
      reussi: viderReussite ? null : (reussi ?? this.reussi),
      depuis: viderDepuis ? null : (depuis ?? this.depuis),
      jusqua: viderJusqua ? null : (jusqua ?? this.jusqua),
      tri: tri ?? this.tri,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FiltreDuJournal &&
      other.recherche == recherche &&
      other.auteurId == auteurId &&
      other.role == role &&
      other.module == module &&
      other.methode == methode &&
      other.reussi == reussi &&
      other.depuis == depuis &&
      other.jusqua == jusqua &&
      other.tri == tri;

  @override
  int get hashCode => Object.hash(
    recherche,
    auteurId,
    role,
    module,
    methode,
    reussi,
    depuis,
    jusqua,
    tri,
  );
}
