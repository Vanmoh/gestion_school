import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/user_account.dart';
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
  int? _selectedUserId;

  static const List<(String, String)> _roles = [
    ('super_admin', 'Super Admin'),
    ('director', 'Directeur'),
    ('accountant', 'Comptable'),
    ('teacher', 'Enseignant'),
    ('supervisor', 'Surveillant'),
    ('parent', 'Parent'),
    ('student', 'Eleve'),
  ];

  @override
  void dispose() {
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
    ref.invalidate(usersProvider);
    try {
      await ref.read(usersProvider.future);
    } catch (_) {
      // Keep pull-to-refresh responsive even when API fails.
    }
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

  String _roleLabel(String role) {
    for (final item in _roles) {
      if (item.$1 == role) {
        return item.$2;
      }
    }
    return role;
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'super_admin':
      case 'director':
        return const Color(0xFF2D6FD6);
      case 'accountant':
        return const Color(0xFF2A8E58);
      case 'teacher':
      case 'supervisor':
        return const Color(0xFF8B5CF6);
      case 'parent':
      case 'student':
        return const Color(0xFFB9721B);
      default:
        return const Color(0xFF546172);
    }
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
    final query = _searchController.text.trim().toLowerCase();

    final rows = users.where((user) {
      if (_roleFilter != 'all' && user.role != _roleFilter) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      final haystack =
          '${user.fullName} ${user.username} ${user.email} ${user.phone}'
              .toLowerCase();
      return haystack.contains(query);
    }).toList();

    rows.sort(
      (left, right) =>
          left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
    );
    return rows;
  }

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
    if (!exists) {
      final fallbackId = rows.first.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedUserId = fallbackId);
      });
    }
  }

  UserAccount? _currentSelectedUser(List<UserAccount> rows) {
    for (final user in rows) {
      if (user.id == _selectedUserId) {
        return user;
      }
    }
    return rows.isEmpty ? null : rows.first;
  }

  void _resetCreateForm() {
    _usernameController.clear();
    _firstNameController.clear();
    _lastNameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _phoneController.clear();
    _selectedRole = 'teacher';
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) {
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
        );

    final mutation = ref.read(userMutationProvider);
    if (mutation.hasError) {
      _showMessage('Erreur creation utilisateur: ${mutation.error}');
      return;
    }

    setState(_resetCreateForm);
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
                              );

                          final mutation = ref.read(userMutationProvider);
                          if (mutation.hasError) {
                            _showMessage(
                              'Erreur modification utilisateur: ${mutation.error}',
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

  Future<void> _deleteUser(UserAccount user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer utilisateur'),
          content: Text('Voulez-vous supprimer le compte "${user.fullName}" ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await ref.read(userMutationProvider.notifier).deleteUser(userId: user.id);

    final mutation = ref.read(userMutationProvider);
    if (mutation.hasError) {
      _showMessage('Erreur suppression utilisateur: ${mutation.error}');
      return;
    }

    if (_selectedUserId == user.id) {
      setState(() => _selectedUserId = null);
    }
    _showMessage('Utilisateur supprime avec succes.', isSuccess: true);
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

  Widget _roleTag(BuildContext context, String role) {
    final color = _roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _roleLabel(role),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
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
      data: (users) {
        final filteredUsers = _filteredUsers(users);
        _syncSelectedUser(filteredUsers);
        final selectedUser = _currentSelectedUser(filteredUsers);

        final totalUsers = users.length;
        final adminCount = users
            .where(
              (user) => user.role == 'super_admin' || user.role == 'director',
            )
            .length;
        final teachingCount = users
            .where(
              (user) => user.role == 'teacher' || user.role == 'supervisor',
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
                      width: 290,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Recherche utilisateur',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                      ),
                    ),
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
                          setState(() => _roleFilter = value ?? 'all');
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: isMutating
                          ? null
                          : () {
                              _searchController.clear();
                              setState(() => _roleFilter = 'all');
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
                  final isWide = constraints.maxWidth >= 1120;

                  final directoryPanel = Container(
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
                        Text(
                          'Annuaire utilisateurs (${filteredUsers.length})',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (filteredUsers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text('Aucun utilisateur correspondant.'),
                            ),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredUsers.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final user = filteredUsers[index];
                              final selected = user.id == _selectedUserId;

                              return Material(
                                color: selected
                                    ? colorScheme.primary.withValues(
                                        alpha: 0.12,
                                      )
                                    : colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    setState(() => _selectedUserId = user.id);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      8,
                                      10,
                                      8,
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          child: Text(_userInitials(user)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                user.fullName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '@${user.username}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _roleTag(context, user.role),
                                        const SizedBox(width: 4),
                                        PopupMenuButton<String>(
                                          tooltip: 'Actions utilisateur',
                                          onSelected: (value) async {
                                            if (value == 'view') {
                                              await _openUserDetails(user);
                                              return;
                                            }
                                            if (value == 'edit') {
                                              await _openEditDialog(user);
                                              return;
                                            }
                                            if (value == 'delete') {
                                              await _deleteUser(user);
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem<String>(
                                              value: 'view',
                                              child: Text('Afficher'),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'edit',
                                              child: Text('Modifier'),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'delete',
                                              child: Text('Supprimer'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );

                  final detailsPanel = Container(
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
                        Text(
                          'Fiche utilisateur',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (selectedUser == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'Selectionnez un utilisateur a gauche.',
                            ),
                          )
                        else ...[
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _metricChip('Nom', selectedUser.fullName),
                              _metricChip('Username', selectedUser.username),
                              _metricChip(
                                'Role',
                                _roleLabel(selectedUser.role),
                              ),
                              _metricChip(
                                'Email',
                                selectedUser.email.isEmpty
                                    ? '-'
                                    : selectedUser.email,
                              ),
                              _metricChip(
                                'Telephone',
                                selectedUser.phone.isEmpty
                                    ? '-'
                                    : selectedUser.phone,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => _openUserDetails(selectedUser),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text('Afficher'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: isMutating
                                    ? null
                                    : () => _openEditDialog(selectedUser),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Modifier'),
                              ),
                              FilledButton.icon(
                                onPressed: isMutating
                                    ? null
                                    : () => _deleteUser(selectedUser),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFB42318),
                                ),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Supprimer'),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
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
                                          setState(() => _selectedRole = value);
                                        }
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

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: directoryPanel),
                        const SizedBox(width: 12),
                        Expanded(flex: 5, child: detailsPanel),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      directoryPanel,
                      const SizedBox(height: 12),
                      detailsPanel,
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
