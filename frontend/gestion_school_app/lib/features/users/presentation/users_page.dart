import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/barre_recherche_module.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../models/etablissement.dart';
import '../domain/user_account.dart';
import 'widgets/dialogue_liste_utilisateurs.dart';
import 'widgets/dialogue_reinitialisation.dart';
import 'widgets/dialogue_suppression.dart';
import 'widgets/pastille_compte.dart';
import 'widgets/user_palette_card.dart';
import 'users_controller.dart';

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {

  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _usernameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedRole = 'teacher';
  String _roleFilter = 'all';
  /// « all », « actifs » ou « desactives ». C'est le filtre qui sort les
  /// comptes restes ouverts apres un depart.
  String _etatFilter = 'all';
  int? _selectedUserId;
  int? _selectedCreateEtablissementId;
  int? _selectedCreateClassroomId;
  final Set<int> _selectedCreateStudentIds = <int>{};
  List<Map<String, dynamic>> _classroomOptions = const [];
  List<Map<String, dynamic>> _studentOptions = const [];
  bool _loadingCreationRefs = false;
  int? _loadedCreationRefsEtablissementId;
  int _currentPage = 1;
  /// Taille de page de la recherche. Fixe depuis que l'annuaire paginé a
  /// quitte l'ecran: on cherche un compte, on n'en feuillette plus des pages.
  static const int _pageSize = 25;
  String _searchTerm = '';
  Timer? _searchDebounce;

  static const List<(String, String)> _roles = [
    ('super_admin', 'Super Admin'),
    ('director', 'Directeur/Proviseur'),
    ('promoter', 'Promoteur'),
    ('accountant', 'Comptable'),
    ('teacher', 'Enseignant'),
    ('censor', 'Censeur'),
    ('supervisor', 'Surveillant'),
    ('parent', 'Parent'),
    ('student', 'Eleve'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncCreationReferences(force: true);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _refreshUsers() async {
    final query = UsersPageQuery(
      page: _currentPage,
      pageSize: _pageSize,
      search: _searchTerm,
      role: _roleFilter == 'all' ? null : _roleFilter,
      actif: switch (_etatFilter) {
        'actifs' => true,
        'desactives' => false,
        _ => null,
      },
    );
    ref.invalidate(usersPaginatedProvider(query));
    try {
      await ref.read(usersPaginatedProvider(query).future);
    } catch (_) {
      // Keep pull-to-refresh responsive even when API fails.
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searchTerm = value.trim();
        _currentPage = 1;
      });
    });
  }

  void _showMessage(String text, {bool isSuccess = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
          backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
        ),
      );
  }

  String _errorText(Object? error) {
    if (error == null) {
      return 'Erreur inconnue';
    }
    final text = error.toString().trim();
    const prefix = 'Exception:';
    if (text.startsWith(prefix)) {
      return text.substring(prefix.length).trim();
    }
    return text;
  }

  String _roleLabel(String role) {
    for (final item in _roles) {
      if (item.$1 == role) {
        return item.$2;
      }
    }
    return role;
  }


  String _userInitials(UserAccount user) {
    final parts = user.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'U';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts[0].substring(0, 1)}${parts[1].substring(0, 1)}'
        .toUpperCase();
  }

  List<UserAccount> _filteredUsers(List<UserAccount> users) {
    final rows = users.toList();

    rows.sort(
      (left, right) =>
          left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
    );
    return rows;
  }

  /// Garde la selection tant qu'elle existe, et ouvre d'office la palette
  /// quand la recherche ne laisse qu'un seul compte.
  ///
  /// L'ecran retombait auparavant sur le premier de la liste: la page
  /// s'ouvrait donc sur la fiche de quelqu'un qu'on n'avait pas demande, et
  /// l'invitation a chercher n'apparaissait jamais. Meme regle que le module
  /// eleve, ou une correspondance unique evite un clic pour rien.
  void _syncSelectedUser(List<UserAccount> rows) {
    if (rows.isEmpty) {
      if (_selectedUserId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedUserId = null);
        });
      }
      return;
    }

    final exists = rows.any((user) => user.id == _selectedUserId);
    if (exists) return;

    final ouvertureDirecte =
        rows.length == 1 && _searchTerm.trim().isNotEmpty ? rows.first.id : null;
    if (_selectedUserId == ouvertureDirecte) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedUserId = ouvertureDirecte);
    });
  }

  UserAccount? _currentSelectedUser(List<UserAccount> rows) {
    for (final user in rows) {
      if (user.id == _selectedUserId) {
        return user;
      }
    }
    // Aucun repli sur le premier: sans choix, la page invite a chercher.
    return null;
  }

  void _resetCreateForm() {
    _usernameController.clear();
    _firstNameController.clear();
    _lastNameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _phoneController.clear();
    _selectedRole = 'teacher';
    _selectedCreateEtablissementId = null;
    _selectedCreateClassroomId = null;
    _selectedCreateStudentIds.clear();
  }

  bool _roleNeedsClassroom(String role) {
    return role == 'student' || role == 'parent';
  }

  bool _roleNeedsStudents(String role) {
    return role == 'parent';
  }

  List<Map<String, dynamic>> _extractRows(dynamic payload) {
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    if (payload is Map && payload['results'] is List) {
      return (payload['results'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _studentDisplayName(Map<String, dynamic> row) {
    final fullName = row['user_full_name']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) {
      return fullName;
    }
    final firstName = row['user_first_name']?.toString().trim() ?? '';
    final lastName = row['user_last_name']?.toString().trim() ?? '';
    final fallback = '$firstName $lastName'.trim();
    if (fallback.isNotEmpty) {
      return fallback;
    }
    final username = row['user_username']?.toString().trim() ?? '';
    if (username.isNotEmpty) {
      return username;
    }
    return 'Eleve #${_asInt(row['id'])}';
  }

  String _classroomDisplayName(int? classroomId) {
    if (classroomId == null) {
      return 'Non selectionnee';
    }
    for (final row in _classroomOptions) {
      if (_asInt(row['id']) == classroomId) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          return name;
        }
      }
    }
    return 'Classe #$classroomId';
  }

  List<String> _selectedStudentNames() {
    if (_selectedCreateStudentIds.isEmpty) {
      return const <String>[];
    }
    final labels = <String>[];
    for (final row in _studentOptions) {
      final id = _asInt(row['id']);
      if (_selectedCreateStudentIds.contains(id)) {
        labels.add(_studentDisplayName(row));
      }
    }
    return labels;
  }

  Future<void> _syncCreationReferences({bool force = false}) async {
    final authUser = ref.read(authControllerProvider).value;
    final selectedEtablissement = ref.read(etablissementProvider).selected;
    final isSuperAdmin = authUser?.role == 'super_admin';
    final etablissementId = isSuperAdmin
        ? (_selectedCreateEtablissementId ?? selectedEtablissement?.id)
        : selectedEtablissement?.id;

    if (!_roleNeedsClassroom(_selectedRole)) {
      if (!mounted) return;
      setState(() {
        _classroomOptions = const [];
        _studentOptions = const [];
        _selectedCreateClassroomId = null;
        _selectedCreateStudentIds.clear();
        _loadedCreationRefsEtablissementId = etablissementId;
        _loadingCreationRefs = false;
      });
      return;
    }

    if (!force &&
        !_loadingCreationRefs &&
        _loadedCreationRefsEtablissementId == etablissementId) {
      return;
    }

    if (etablissementId == null) {
      if (!mounted) return;
      setState(() {
        _classroomOptions = const [];
        _studentOptions = const [];
        _selectedCreateClassroomId = null;
        _selectedCreateStudentIds.clear();
        _loadedCreationRefsEtablissementId = null;
        _loadingCreationRefs = false;
      });
      return;
    }

    setState(() => _loadingCreationRefs = true);
    final dio = ref.read(dioProvider);

    try {
      final responses = await Future.wait<Response<dynamic>>(<Future<Response<dynamic>>>[
        dio.get('/classrooms/?etablissement=$etablissementId&page_size=500'),
        dio.get('/students/?etablissement=$etablissementId&page_size=500'),
      ]);

      final classrooms = _extractRows(responses[0].data);
      final students = _extractRows(responses[1].data);

      if (!mounted) return;
      setState(() {
        _classroomOptions = classrooms;
        _studentOptions = students;
        final hasClassroomSelection = classrooms.any(
          (row) => _asInt(row['id']) == _selectedCreateClassroomId,
        );
        if (!hasClassroomSelection) {
          _selectedCreateClassroomId = null;
        }

        final allowedStudentIds = students
            .map((row) => _asInt(row['id']))
            .where((id) => id > 0)
            .toSet();
        _selectedCreateStudentIds.removeWhere((id) => !allowedStudentIds.contains(id));

        _loadedCreationRefsEtablissementId = etablissementId;
      });
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() {
        _classroomOptions = const [];
        _studentOptions = const [];
        _selectedCreateClassroomId = null;
        _selectedCreateStudentIds.clear();
        _loadedCreationRefsEtablissementId = etablissementId;
      });
      _showMessage('Impossible de charger classes/eleves pour cet etablissement.');
    } finally {
      if (mounted) {
        setState(() => _loadingCreationRefs = false);
      }
    }
  }

  Future<void> _openStudentMultiSelectDialog() async {
    if (_studentOptions.isEmpty) {
      _showMessage('Aucun eleve disponible pour cet etablissement.');
      return;
    }

    final selected = Set<int>.from(_selectedCreateStudentIds);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Selectionner un ou plusieurs eleves'),
              content: SizedBox(
                width: 460,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _studentOptions.length,
                  itemBuilder: (context, index) {
                    final row = _studentOptions[index];
                    final studentId = _asInt(row['id']);
                    final label = _studentDisplayName(row);
                    final classLabel = row['classroom_name']?.toString().trim() ?? '';
                    return CheckboxListTile(
                      dense: true,
                      value: selected.contains(studentId),
                      title: Text(label),
                      subtitle: classLabel.isEmpty ? null : Text(classLabel),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(studentId);
                          } else {
                            selected.remove(studentId);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Valider'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        _selectedCreateStudentIds
          ..clear()
          ..addAll(selected);
      });
    }
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authUser = ref.read(authControllerProvider).value;
    final selectedEtablissement = ref.read(etablissementProvider).selected;
    final isSuperAdmin = authUser?.role == 'super_admin';
    final etablissementId = isSuperAdmin
        ? (_selectedCreateEtablissementId ?? selectedEtablissement?.id)
        : selectedEtablissement?.id;

    if (etablissementId == null) {
      _showMessage('Aucun etablissement actif pour creer cet utilisateur.');
      return;
    }

    if (_roleNeedsClassroom(_selectedRole) && _selectedCreateClassroomId == null) {
      _showMessage('Selectionnez une classe pour ce role.');
      return;
    }
    if (_roleNeedsStudents(_selectedRole) && _selectedCreateStudentIds.isEmpty) {
      _showMessage('Selectionnez au moins un eleve pour ce parent.');
      return;
    }

    await ref
        .read(userMutationProvider.notifier)
        .createUser(
          username: _usernameController.text.trim(),
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          role: _selectedRole,
          phone: _phoneController.text.trim(),
          etablissementId: etablissementId,
          classroomId: _roleNeedsClassroom(_selectedRole)
              ? _selectedCreateClassroomId
              : null,
          studentIds: _roleNeedsStudents(_selectedRole)
              ? _selectedCreateStudentIds.toList(growable: false)
              : null,
        );

    final mutation = ref.read(userMutationProvider);
    if (mutation.hasError) {
      _showMessage('Erreur creation utilisateur: ${_errorText(mutation.error)}');
      return;
    }

    setState(_resetCreateForm);
    unawaited(_syncCreationReferences(force: true));
    _showMessage('Utilisateur cree avec succes.', isSuccess: true);
  }

  Future<void> _openUserDetails(UserAccount user) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Details utilisateur'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Nom complet', user.fullName),
                _detailRow('Username', user.username),
                _detailRow('Role', _roleLabel(user.role)),
                _detailRow(
                  'Etablissement',
                  user.etablissementName.trim().isEmpty
                      ? '-'
                      : user.etablissementName,
                ),
                _detailRow('Email', user.email.isEmpty ? '-' : user.email),
                _detailRow('Telephone', user.phone.isEmpty ? '-' : user.phone),
                _detailRow('ID', '${user.id}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEditDialog(UserAccount user) async {
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController(text: user.username);
    final firstNameController = TextEditingController(text: user.firstName);
    final lastNameController = TextEditingController(text: user.lastName);
    final emailController = TextEditingController(text: user.email);
    final phoneController = TextEditingController(text: user.phone);
    var editRole = user.role;
    final authUser = ref.read(authControllerProvider).value;
    final selectedEtablissement = ref.read(etablissementProvider).selected;
    final isSuperAdmin = authUser?.role == 'super_admin';
    var editEtablissementId = user.etablissementId ?? selectedEtablissement?.id;
    var saving = false;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Modifier utilisateur'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: firstNameController,
                        decoration: const InputDecoration(labelText: 'Prenom'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: lastNameController,
                        decoration: const InputDecoration(labelText: 'Nom'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Telephone',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: editRole,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: _roles
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item.$1,
                                child: Text(item.$2),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => editRole = value);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        initialValue: editEtablissementId,
                        decoration: const InputDecoration(
                          labelText: 'Etablissement',
                        ),
                        items: ref
                            .read(etablissementProvider)
                            .etablissements
                            .map(
                              (etab) => DropdownMenuItem<int>(
                                value: etab.id,
                                child: Text(etab.name),
                              ),
                            )
                            .toList(),
                        onChanged: !isSuperAdmin
                            ? null
                            : (value) {
                                setDialogState(
                                  () => editEtablissementId = value,
                                );
                              },
                        validator: (value) {
                          if (value == null) {
                            return 'Etablissement requis';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          setDialogState(() => saving = true);

                          await ref
                              .read(userMutationProvider.notifier)
                              .updateUser(
                                userId: user.id,
                                username: usernameController.text.trim(),
                                firstName: firstNameController.text.trim(),
                                lastName: lastNameController.text.trim(),
                                email: emailController.text.trim(),
                                role: editRole,
                                phone: phoneController.text.trim(),
                                etablissementId: isSuperAdmin
                                    ? editEtablissementId
                                    : selectedEtablissement?.id,
                              );

                          final mutation = ref.read(userMutationProvider);
                          if (mutation.hasError) {
                            _showMessage(
                              'Erreur modification utilisateur: ${_errorText(mutation.error)}',
                            );
                            setDialogState(() => saving = false);
                            return;
                          }

                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    phoneController.dispose();

    if (updated == true) {
      _showMessage('Utilisateur modifie avec succes.', isSuccess: true);
    }
  }

  /// La suppression dit d'abord ce qu'elle emporte.
  ///
  /// Elle demandait « Voulez-vous supprimer ce compte ? » sans dire que
  /// `Student.user` et `Teacher.user` sont en CASCADE: le compte d'un
  /// enseignant partait avec sa fiche, ses affectations, ses creneaux et ses
  /// pointages, sans que rien ne l'annonce.
  Future<void> _deleteUser(UserAccount user) async {
    final controleur = ref.read(userMutationProvider.notifier);

    Map<String, int> lie;
    try {
      lie = await controleur.donneesLiees(user.id) ?? const {};
    } catch (erreur) {
      _showMessage('Erreur suppression utilisateur: ${_errorText(erreur)}');
      return;
    }

    // L'inventaire est vide et le serveur a deja supprime le compte: rien de
    // plus a demander.
    if (lie.isEmpty) {
      ref.invalidate(usersProvider);
      ref.invalidate(usersPaginatedProvider);
      if (_selectedUserId == user.id) {
        setState(() => _selectedUserId = null);
      }
      _showMessage('Compte supprimé.', isSuccess: true);
      return;
    }

    if (!mounted) return;
    final choix = await showDialog<ChoixSuppression>(
      context: context,
      builder: (_) => DialogueSuppression(compte: user, donneesLiees: lie),
    );
    if (choix == null) return;

    if (choix == ChoixSuppression.desactiver) {
      await _setActive(user, false);
      return;
    }

    await controleur.deleteUser(userId: user.id, confirme: true);

    final mutation = ref.read(userMutationProvider);
    if (mutation.hasError) {
      _showMessage(
        'Erreur suppression utilisateur: ${_errorText(mutation.error)}',
      );
      return;
    }

    if (_selectedUserId == user.id) {
      setState(() => _selectedUserId = null);
    }
    _showMessage('Compte supprimé avec ses données liées.', isSuccess: true);
  }

  /// Retire ou rend l'acces sans effacer ce que la personne a produit.
  ///
  /// C'etait impossible: l'ecran n'offrait pas l'action, et l'API repondait
  /// 200 a une demande de desactivation sans rien changer.
  Future<void> _setActive(UserAccount user, bool actif) async {
    await ref
        .read(userMutationProvider.notifier)
        .setActive(userId: user.id, actif: actif);

    final mutation = ref.read(userMutationProvider);
    if (mutation.hasError) {
      _showMessage(_errorText(mutation.error));
      return;
    }
    _showMessage(
      actif
          ? 'Compte réactivé : ${user.fullName} peut se reconnecter.'
          : 'Compte désactivé : ${user.fullName} ne peut plus se connecter.',
      isSuccess: true,
    );
  }

  /// L'administration fixe un mot de passe provisoire, qu'elle communique.
  Future<void> _resetPassword(UserAccount user) async {
    final motDePasse = await showDialog<String>(
      context: context,
      builder: (_) => DialogueReinitialisation(compte: user),
    );
    if (motDePasse == null || !mounted) return;

    final message = await ref
        .read(userMutationProvider.notifier)
        .resetPassword(userId: user.id, motDePasse: motDePasse);

    final mutation = ref.read(userMutationProvider);
    if (mutation.hasError) {
      _showMessage(_errorText(mutation.error));
      return;
    }
    _showMessage(message ?? 'Mot de passe réinitialisé.', isSuccess: true);
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Ouvre l'annuaire complet et ramene le compte choisi dans la palette.
  ///
  /// La page s'ouvre sur une recherche; parcourir tous les comptes reste
  /// pourtant necessaire -- reperer un acces reste ouvert, par exemple --
  /// et se fait desormais ici.
  Future<void> _ouvrirListeUtilisateurs() async {
    final choisi = await DialogueListeUtilisateurs.ouvrir(
      context,
      roleFiltre: _roleFilter,
      etatFiltre: _etatFilter,
      libelleRole: _roleLabel,
    );
    if (!mounted || choisi == null) return;

    // La recherche est cadree sur l'identifiant du compte choisi: sans cela
    // il ne ferait pas partie de la page courante et la palette resterait
    // vide.
    _searchDebounce?.cancel();
    _searchController.text = choisi.username;
    setState(() {
      _searchTerm = choisi.username;
      _currentPage = 1;
      _selectedUserId = choisi.id;
    });
  }

  /// Les correspondances a departager, quand la recherche en laisse plusieurs.
  Widget _carteCorrespondances(List<UserAccount> comptes) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${comptes.length} comptes correspondent',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Choisissez celui dont vous voulez ouvrir la palette.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final compte in comptes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                leading: CircleAvatar(child: Text(_userInitials(compte))),
                title: Text(
                  compte.fullName.trim().isEmpty
                      ? compte.username
                      : compte.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${compte.username} · ${_roleLabel(compte.role)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: PastilleCompte(compte: compte),
                onTap: () => setState(() => _selectedUserId = compte.id),
              ),
          ],
        ),
      ),
    );
  }

  /// Les boutons d'ecriture de la palette, dans l'ordre du quotidien:
  /// consulter, corriger, puis les gestes qui engagent.
  List<Widget> _actionsPalette(UserAccount compte, bool enCours) {
    return [
      FilledButton.tonalIcon(
        onPressed: () => _openUserDetails(compte),
        icon: const Icon(Icons.visibility_outlined),
        label: const Text('Afficher'),
      ),
      FilledButton.tonalIcon(
        onPressed: enCours ? null : () => _openEditDialog(compte),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Modifier'),
      ),
      // Ces deux-la vivaient dans le menu contextuel de l'annuaire, qui a
      // quitte la page: sans elles, retirer un acces ou depanner quelqu'un
      // n'aurait plus eu de porte d'entree.
      OutlinedButton.icon(
        onPressed: enCours ? null : () => _resetPassword(compte),
        icon: const Icon(Icons.password_outlined),
        label: const Text('Réinitialiser le mot de passe'),
      ),
      OutlinedButton.icon(
        onPressed: enCours
            ? null
            : () => _setActive(compte, !compte.isActive),
        icon: Icon(
          compte.isActive ? Icons.lock_outline : Icons.lock_open_outlined,
        ),
        label: Text(
          compte.isActive ? 'Désactiver le compte' : 'Réactiver le compte',
        ),
      ),
      FilledButton.icon(
        onPressed: enCours
            ? null
            : () => _deleteUser(compte),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB42318),
        ),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Supprimer'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider).value;
    final selectedEtablissement = ref.watch(etablissementProvider).selected;
    final allEtablissements = ref.watch(etablissementProvider).etablissements;
    final isSuperAdmin = authUser?.role == 'super_admin';

    final effectiveCreateEtablissementId = isSuperAdmin
        ? (_selectedCreateEtablissementId ?? selectedEtablissement?.id)
        : selectedEtablissement?.id;
    if (_roleNeedsClassroom(_selectedRole) &&
        !_loadingCreationRefs &&
        _loadedCreationRefsEtablissementId != effectiveCreateEtablissementId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_syncCreationReferences(force: true));
      });
    }

    final query = UsersPageQuery(
      page: _currentPage,
      pageSize: _pageSize,
      search: _searchTerm,
      role: _roleFilter == 'all' ? null : _roleFilter,
      actif: switch (_etatFilter) {
        'actifs' => true,
        'desactives' => false,
        _ => null,
      },
    );
    final usersAsync = ref.watch(usersPaginatedProvider(query));
    final mutationState = ref.watch(userMutationProvider);
    final isMutating = mutationState.isLoading;
    final colorScheme = Theme.of(context).colorScheme;

    return usersAsync.when(
      loading: () => RefreshIndicator(
        onRefresh: _refreshUsers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: const [
            SizedBox(
              height: 460,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
      error: (error, _) => RefreshIndicator(
        onRefresh: _refreshUsers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impossible de charger les utilisateurs',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Erreur: $error'),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _refreshUsers,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reessayer'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      data: (pageData) {
        final users = pageData.results;
        final existingUsernames = users
          .map((user) => user.username.trim().toLowerCase())
          .where((username) => username.isNotEmpty)
          .toSet();
        final filteredUsers = _filteredUsers(users);
        _syncSelectedUser(filteredUsers);
        final selectedUser = _currentSelectedUser(filteredUsers);

        final totalUsers = pageData.count;
        final adminCount = users
            .where(
              (user) =>
                  user.role == 'super_admin' ||
                  user.role == 'director' ||
                  user.role == 'promoter',
            )
            .length;
        final teachingCount = users
            .where(
              (user) =>
                  user.role == 'teacher' ||
                  user.role == 'censor' ||
                  user.role == 'supervisor',
            )
            .length;
        final familyCount = users
            .where((user) => user.role == 'parent' || user.role == 'student')
            .length;

        return RefreshIndicator(
          onRefresh: _refreshUsers,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              Text(
                'Gestion des utilisateurs',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Annuaire comptes, profil detaille et administration des acces.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metricChip('Total comptes', '$totalUsers'),
                    _metricChip('Direction/Admin', '$adminCount'),
                    _metricChip('Pedagogie', '$teachingCount'),
                    _metricChip('Parents/Eleves', '$familyCount'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Le point d'entree du module, comme chez les eleves et les
              // enseignants: on arrive avec un nom en tete. Les filtres role
              // et etat restent dessous, ils cadrent la recherche sans la
              // remplacer.
              BarreRechercheModule(
                controller: _searchController,
                indication:
                    'Rechercher un utilisateur : nom, identifiant, e-mail, téléphone…',
                onChanged: _onSearchChanged,
                onEffacer: () {
                  _searchDebounce?.cancel();
                  _searchController.clear();
                  setState(() {
                    _searchTerm = '';
                    _currentPage = 1;
                    _selectedUserId = null;
                  });
                },
                compact: MediaQuery.sizeOf(context).width < 720,
                actions: [
                  OutlinedButton.icon(
                    onPressed: _ouvrirListeUtilisateurs,
                    icon: const Icon(Icons.groups_2_outlined),
                    label: const Text('Liste des utilisateurs'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        initialValue: _roleFilter,
                        decoration: const InputDecoration(
                          labelText: 'Filtrer par role',
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'all',
                            child: Text('Tous les roles'),
                          ),
                          ..._roles.map(
                            (item) => DropdownMenuItem<String>(
                              value: item.$1,
                              child: Text(item.$2),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _roleFilter = value ?? 'all';
                            _currentPage = 1;
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        key: const Key('filtre-etat-compte'),
                        initialValue: _etatFilter,
                        decoration: const InputDecoration(
                          labelText: 'État du compte',
                        ),
                        items: const [
                          DropdownMenuItem<String>(
                            value: 'all',
                            child: Text('Tous les états'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'actifs',
                            child: Text('Actifs'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'desactives',
                            child: Text('Désactivés'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _etatFilter = value ?? 'all';
                            _currentPage = 1;
                          });
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: isMutating
                          ? null
                          : () {
                              _searchDebounce?.cancel();
                              _searchController.clear();
                              setState(() {
                                _roleFilter = 'all';
                                _searchTerm = '';
                                _currentPage = 1;
                              });
                            },
                      icon: const Icon(Icons.filter_alt_off_outlined),
                      label: const Text('Reinitialiser'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {


                  // Le panneau ne porte plus que la creation: l'identite et
                  // les actions d'un compte vivent desormais dans sa palette,
                  // au-dessus.
                  final panneauCreation = Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: colorScheme.outlineVariant),
                        const SizedBox(height: 10),
                        Text(
                          'Creer un utilisateur',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  SizedBox(
                                    width: 220,
                                    child: TextFormField(
                                      controller: _usernameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Nom utilisateur',
                                      ),
                                      validator: (value) =>
                                          (value == null ||
                                            value.trim().isEmpty)
                                          ? 'Champ requis'
                                          : existingUsernames.contains(
                                            value.trim().toLowerCase(),
                                          )
                                          ? 'Ce nom utilisateur existe deja'
                                          : null,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 170,
                                    child: TextFormField(
                                      controller: _firstNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Prenom',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 170,
                                    child: TextFormField(
                                      controller: _lastNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Nom',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 250,
                                    child: TextFormField(
                                      controller: _emailController,
                                      decoration: const InputDecoration(
                                        labelText: 'Email',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 200,
                                    child: TextFormField(
                                      controller: _phoneController,
                                      decoration: const InputDecoration(
                                        labelText: 'Telephone',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedRole,
                                      decoration: const InputDecoration(
                                        labelText: 'Role',
                                      ),
                                      items: _roles
                                          .map(
                                            (item) => DropdownMenuItem<String>(
                                              value: item.$1,
                                              child: Text(item.$2),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() {
                                            _selectedRole = value;
                                            _selectedCreateClassroomId = null;
                                            _selectedCreateStudentIds.clear();
                                          });
                                          unawaited(_syncCreationReferences(force: true));
                                        }
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 280,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: isSuperAdmin
                                          ? (_selectedCreateEtablissementId ??
                                                selectedEtablissement?.id)
                                          : selectedEtablissement?.id,
                                      decoration: const InputDecoration(
                                        labelText: 'Etablissement',
                                      ),
                                      items: allEtablissements
                                          .map(
                                            (etab) => DropdownMenuItem<int>(
                                              value: etab.id,
                                              child: Text(etab.name),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: !isSuperAdmin
                                          ? null
                                          : (value) {
                                              setState(() {
                                                _selectedCreateEtablissementId =
                                                    value;
                                                _selectedCreateClassroomId = null;
                                                _selectedCreateStudentIds.clear();
                                              });
                                              unawaited(_syncCreationReferences(force: true));
                                            },
                                      validator: (value) {
                                        if ((value ??
                                                selectedEtablissement?.id) ==
                                            null) {
                                          return 'Etablissement requis';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 220,
                                    child: TextFormField(
                                      controller: _passwordController,
                                      obscureText: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Mot de passe',
                                      ),
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().length < 8) {
                                          return '8 caracteres minimum';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_roleNeedsClassroom(_selectedRole))
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedRole == 'student'
                                            ? 'Champs supplementaires eleve'
                                            : 'Champs supplementaires parent',
                                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 320,
                                            child: DropdownButtonFormField<int>(
                                              initialValue: _selectedCreateClassroomId,
                                              decoration: const InputDecoration(
                                                labelText: 'Classe (obligatoire)',
                                              ),
                                              items: _classroomOptions
                                                  .map(
                                                    (row) => DropdownMenuItem<int>(
                                                      value: _asInt(row['id']),
                                                      child: Text(
                                                        row['name']?.toString() ??
                                                            'Classe #${_asInt(row['id'])}',
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                              onChanged: _loadingCreationRefs
                                                  ? null
                                                  : (value) {
                                                      setState(
                                                        () => _selectedCreateClassroomId = value,
                                                      );
                                                    },
                                              validator: (value) {
                                                if (_roleNeedsClassroom(_selectedRole) &&
                                                    value == null) {
                                                  return 'Classe requise';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          if (_roleNeedsStudents(_selectedRole))
                                            SizedBox(
                                              width: 350,
                                              child: FormField<Set<int>>(
                                                initialValue: _selectedCreateStudentIds,
                                                validator: (_) {
                                                  if (_roleNeedsStudents(_selectedRole) &&
                                                      _selectedCreateStudentIds.isEmpty) {
                                                    return 'Selectionnez au moins un eleve';
                                                  }
                                                  return null;
                                                },
                                                builder: (field) {
                                                  final selectedNames = _selectedStudentNames();
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      OutlinedButton.icon(
                                                        onPressed: _loadingCreationRefs
                                                            ? null
                                                            : () async {
                                                                await _openStudentMultiSelectDialog();
                                                                field.didChange(
                                                                  Set<int>.from(_selectedCreateStudentIds),
                                                                );
                                                              },
                                                        icon: const Icon(Icons.groups_2_outlined),
                                                        label: Text(
                                                          _selectedCreateStudentIds.isEmpty
                                                              ? 'Selectionner les eleves (obligatoire)'
                                                              : '${_selectedCreateStudentIds.length} eleve(s) selectionne(s)',
                                                        ),
                                                      ),
                                                      if (selectedNames.isNotEmpty) ...[
                                                        const SizedBox(height: 8),
                                                        Wrap(
                                                          spacing: 6,
                                                          runSpacing: 6,
                                                          children: selectedNames
                                                              .map((name) => Chip(label: Text(name)))
                                                              .toList(growable: false),
                                                        ),
                                                      ],
                                                      if (field.errorText != null)
                                                        Padding(
                                                          padding: const EdgeInsets.only(top: 6),
                                                          child: Text(
                                                            field.errorText!,
                                                            style: TextStyle(
                                                              color: Theme.of(context).colorScheme.error,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _selectedRole == 'student'
                                            ? 'Un eleve doit obligatoirement etre associe a une classe.'
                                            : 'Un parent doit avoir une classe de reference et au moins un eleve. Les eleves peuvent venir de classes differentes.',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                      if (_selectedCreateClassroomId != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Classe selectionnee: ${_classroomDisplayName(_selectedCreateClassroomId)}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              if (_roleNeedsClassroom(_selectedRole) && _loadingCreationRefs)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: LinearProgressIndicator(minHeight: 2),
                                ),
                              if (!isSuperAdmin &&
                                  selectedEtablissement != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    'Les nouveaux comptes seront crees dans: ${selectedEtablissement.name}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              FilledButton.icon(
                                onPressed: isMutating ? null : _createUser,
                                icon: isMutating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person_add_alt_1_outlined,
                                      ),
                                label: const Text('Creer utilisateur'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );

                  // Trois etats, comme chez les eleves: le compte choisi,
                  // les correspondances a departager, ou l'invitation a
                  // chercher. La creation suit, elle ne depend d'aucun choix.
                  final Widget zoneResultat;
                  if (selectedUser != null) {
                    zoneResultat = UserPaletteCard(
                      compte: selectedUser,
                      actions: _actionsPalette(selectedUser, isMutating),
                      onClear: filteredUsers.length > 1
                          ? () => setState(() => _selectedUserId = null)
                          : null,
                    );
                  } else if (_searchTerm.trim().isNotEmpty &&
                      filteredUsers.length > 1) {
                    zoneResultat = _carteCorrespondances(filteredUsers);
                  } else {
                    zoneResultat = EtatVideRecherche(
                      recherche: _searchTerm,
                      invitation:
                          'Recherchez un utilisateur pour ouvrir sa palette.',
                      precision: 'Nom, identifiant, e-mail ou téléphone.',
                      motAucun: 'Aucun utilisateur ne correspond à',
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      zoneResultat,
                      const SizedBox(height: 12),
                      panneauCreation,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
