import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_constants.dart';
import '../network/api_client.dart';
import '../../features/auth/presentation/auth_controller.dart';

/// Droits du profil connecte, tels que le backend les applique.
///
/// Le menu et les boutons d'action lisaient jusqu'ici une carte des roles
/// codee en dur dans app.dart, qui divergeait silencieusement du backend:
/// un module pouvait s'afficher en « lecture seule » tout en acceptant les
/// ecritures, ou l'inverse. Ici il n'y a plus qu'une source, servie par
/// GET /auth/permissions/.
enum AccessLevel { none, read, write, admin }

class ModulePermission {
  final String key;
  final String label;
  final String group;
  final AccessLevel level;

  /// Acces limite au perimetre personnel (ses classes, ses enfants, soi).
  final bool scoped;

  const ModulePermission({
    required this.key,
    required this.label,
    required this.group,
    required this.level,
    required this.scoped,
  });

  bool get canRead => level.index >= AccessLevel.read.index;
  bool get canWrite => level.index >= AccessLevel.write.index;
  bool get canDelete => level.index >= AccessLevel.admin.index;
  bool get isReadOnly => canRead && !canWrite;

  static const ModulePermission denied = ModulePermission(
    key: '',
    label: '',
    group: '',
    level: AccessLevel.none,
    scoped: false,
  );

  factory ModulePermission.fromJson(String key, Map<String, dynamic> json) {
    return ModulePermission(
      key: key,
      label: (json['label'] ?? key).toString(),
      group: (json['group'] ?? '').toString(),
      level: _levelFromName(json['level']),
      scoped: json['scoped'] == true,
    );
  }

  static AccessLevel _levelFromName(Object? raw) {
    switch (raw?.toString()) {
      case 'admin':
        return AccessLevel.admin;
      case 'write':
        return AccessLevel.write;
      case 'read':
        return AccessLevel.read;
      default:
        return AccessLevel.none;
    }
  }
}

class ModulePermissions {
  final String role;
  final Map<String, ModulePermission> modules;

  /// Prefixes d'URL par module, calcules par le backend a partir de son
  /// propre routage. Recopier cette table ici aurait recree la divergence
  /// que toute cette matrice sert a supprimer.
  final Map<String, List<String>> paths;

  /// Gestes precis a l'interieur d'un module deja ouvert: valider la paie au
  /// niveau 1, noter la conduite, lancer un export nominatif.
  ///
  /// La matrice n'a que quatre niveaux par module et ne sait pas les
  /// exprimer. Sans cette table, un bouton d'export s'affichait pour tous et
  /// ne refusait qu'au clic.
  final Map<String, bool> capabilities;

  const ModulePermissions({
    required this.role,
    required this.modules,
    this.paths = const {},
    this.capabilities = const {},
  });

  static const ModulePermissions empty = ModulePermissions(
    role: '',
    modules: {},
  );

  /// Un geste inconnu du serveur est refuse: comme pour les modules, on
  /// echoue ferme plutot que d'afficher un bouton qui rendra 403.
  bool can(String capability) => capabilities[capability] ?? false;

  /// Route CRUD simple: la collection ou un element ("/grades/", "/grades/12/").
  static final RegExp _crudTail = RegExp(r'^/?$|^/\d+/?$');

  /// Module gouvernant une ecriture sur ce chemin, s'il est certain.
  ///
  /// Volontairement limite aux routes CRUD: les sous-actions ("valider le
  /// niveau 1", "feuille d'appel") portent leurs propres regles cote serveur,
  /// et le client n'a pas a les deviner. En cas de doute, on laisse passer et
  /// le backend tranche.
  String? moduleGoverningWrite(String path) {
    final clean = path.split('?').first;
    for (final entry in paths.entries) {
      for (final prefix in entry.value) {
        if (!clean.startsWith(prefix)) {
          continue;
        }
        if (_crudTail.hasMatch(clean.substring(prefix.length))) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Un module inconnu du serveur est refuse: on echoue ferme, comme le
  /// backend, plutot que d'afficher une entree qui rendra 403 au clic.
  ModulePermission of(String key) => modules[key] ?? ModulePermission.denied;

  bool canRead(String key) => of(key).canRead;
  bool canWrite(String key) => of(key).canWrite;
  bool canDelete(String key) => of(key).canDelete;
  bool isReadOnly(String key) => of(key).isReadOnly;

  factory ModulePermissions.fromJson(Map<String, dynamic> json) {
    final rawModules = (json['modules'] as Map?) ?? const {};
    final rawPaths = (json['paths'] as Map?) ?? const {};
    final rawCapabilities = (json['capabilities'] as Map?) ?? const {};
    return ModulePermissions(
      role: (json['role'] ?? '').toString(),
      capabilities: {
        for (final entry in rawCapabilities.entries)
          entry.key.toString(): entry.value == true,
      },
      modules: {
        for (final entry in rawModules.entries)
          entry.key.toString(): ModulePermission.fromJson(
            entry.key.toString(),
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
      paths: {
        for (final entry in rawPaths.entries)
          entry.key.toString(): [
            for (final path in (entry.value as List)) path.toString(),
          ],
      },
    );
  }
}

/// Matrice courante, accessible hors arbre Riverpod.
///
/// L'intercepteur reseau en a besoin, or il est construit par le provider Dio
/// dont depend le chargement de la matrice: passer par ce relais evite la
/// dependance circulaire.
class ModulePermissionsRegistry {
  ModulePermissionsRegistry._();

  static ModulePermissions current = ModulePermissions.empty;

  /// Ecriture certainement refusee par la matrice, avec son message.
  ///
  /// Renvoie null quand rien ne s'y oppose ou que le chemin ne se rattache
  /// pas a coup sur a un module: le backend reste l'autorite.
  static String? refusalFor(String method, String path) {
    const writeMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};
    if (!writeMethods.contains(method.toUpperCase())) {
      return null;
    }

    final permissions = current;
    final module = permissions.moduleGoverningWrite(path);
    if (module == null) {
      return null;
    }

    final entry = permissions.of(module);
    if (method.toUpperCase() == 'DELETE' && !entry.canDelete) {
      return entry.canWrite
          ? 'Suppression sur « ${entry.label} » reservee a l\'administration.'
          : 'Module « ${entry.label} » non modifiable par votre profil.';
    }
    if (!entry.canWrite) {
      return entry.canRead
          ? 'Module « ${entry.label} » en lecture seule pour votre profil.'
          : 'Module non accessible a votre profil.';
    }
    return null;
  }
}

/// Recharge des que l'utilisateur connecte change: se deconnecter puis se
/// reconnecter sous un autre profil ne doit pas laisser trainer les droits
/// du precedent.
final modulePermissionsProvider = FutureProvider<ModulePermissions>((ref) async {
  final user = ref.watch(authControllerProvider).value;
  if (user == null) {
    // Deconnexion: ne pas laisser trainer les droits du profil precedent.
    ModulePermissionsRegistry.current = ModulePermissions.empty;
    return ModulePermissions.empty;
  }

  final dio = ref.read(dioProvider);
  final response = await dio.get<Map<String, dynamic>>(ApiConstants.permissions);
  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Reponse de permissions vide.',
    );
  }
  final permissions = ModulePermissions.fromJson(data);
  ModulePermissionsRegistry.current = permissions;
  return permissions;
});

/// Ce que la coquille doit afficher en attendant, ou a la place, du menu.
enum PermissionsGate { loading, unavailable, noModule, ready }

/// Traduit l'etat du provider en decision d'affichage.
///
/// Extrait de la coquille parce que l'ordre des tests est tout le sujet: le
/// provider rend d'abord une matrice vide (personne n'est connecte au premier
/// build), et Riverpod conserve cette valeur quand la requete suivante echoue.
/// Un `hasValue` teste avant `hasError` laissait donc passer l'echec, et la
/// barre laterale s'affichait sans un seul module ni le moindre message.
PermissionsGate permissionsGate(
  AsyncValue<ModulePermissions> state, {
  required bool hasVisibleModule,
}) {
  if (state.hasError) {
    return PermissionsGate.unavailable;
  }
  if (state.isLoading || !state.hasValue) {
    return PermissionsGate.loading;
  }
  if (!hasVisibleModule) {
    return PermissionsGate.noModule;
  }
  return PermissionsGate.ready;
}

/// Vue synchrone pour les widgets de rendu: tant que la matrice n'est pas
/// chargee, aucun droit n'est accorde.
final currentPermissionsProvider = Provider<ModulePermissions>((ref) {
  return ref.watch(modulePermissionsProvider).valueOrNull ??
      ModulePermissions.empty;
});

/// Les gestes affines, nommes une fois.
///
/// Les clefs viennent de `AFFINEMENTS` cote serveur; les ecrire en toutes
/// lettres a chaque bouton aurait remis une chaine litterale a corriger
/// partout le jour ou l'une d'elles change.
class Capacites {
  Capacites._();

  /// Exports nominatifs et financiers: journal des paiements et des
  /// depenses, classeur Excel, liste imprimable du personnel.
  static const exportsSensibles = 'exports_sensibles';
  static const validationPaieNiveau1 = 'validation_paie_niveau_1';
  static const validationPaieNiveau2 = 'validation_paie_niveau_2';

  /// Defaire une double validation efface la trace de qui avait signe:
  /// aucun des deux signataires ne s'en charge lui-meme.
  static const annulationValidationPaie = 'annulation_validation_paie';
  static const annulationValidationDepense = 'annulation_validation_depense';

  static const saisieConduite = 'saisie_conduite';
  static const appelAttention = 'appel_attention';
}
