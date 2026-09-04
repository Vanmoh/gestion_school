part of 'teachers_page.dart';

/// La création du compte d'un enseignant.
///
/// Elle touche aux identifiants, pas au dossier pédagogique.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit
/// les champs de la page comme avant.
extension _DialogueDuCompte on _TeachersPageState {
  Future<bool> _openCreateTeacherUserDialog() async {
    final usernameController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    Uint8List? photoBytes;
    String? photoPath;
    String? photoFileName;
    int? createdUserId;
    String createdUsername = '';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        var savingDialog = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ajouter un compte enseignant'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: usernameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Username *',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: emailController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Email (facultatif)',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: firstNameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Prénom *',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: lastNameController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(labelText: 'Nom *'),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: phoneController,
                          enabled: !savingDialog,
                          decoration: const InputDecoration(
                            labelText: 'Téléphone',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: passwordController,
                          enabled: !savingDialog,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mot de passe *',
                          ),
                        ),
                      ),
                      // La photo est televersee apres la creation du compte:
                      // /auth/register/ recoit du JSON, un fichier demande du
                      // multipart. Elle est facultative -- une fiche sans
                      // portrait reste une fiche.
                      _PhotoField(
                        bytes: photoBytes,
                        fileName: photoFileName,
                        enabled: !savingDialog,
                        onPick: () async {
                          final choix = await _pickTeacherPhoto();
                          if (choix == null) return;
                          setDialogState(() {
                            photoBytes = choix.bytes;
                            photoPath = choix.path;
                            photoFileName = choix.fileName;
                          });
                        },
                        onClear: () => setDialogState(() {
                          photoBytes = null;
                          photoPath = null;
                          photoFileName = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingDialog
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingDialog
                      ? null
                      : () async {
                          final username = usernameController.text.trim();
                          createdUsername = username.toLowerCase();
                          final firstName = firstNameController.text.trim();
                          final lastName = lastNameController.text.trim();
                          final email = emailController.text.trim();
                          final phone = phoneController.text.trim();
                          final password = passwordController.text;

                          // L'email n'est pas exige: beaucoup d'enseignants
                          // n'en ont pas, et le reclamer poussait a inventer
                          // une adresse qui ne servira jamais.
                          if (username.isEmpty ||
                              firstName.isEmpty ||
                              lastName.isEmpty ||
                              password.isEmpty) {
                            _showMessage(
                              'Complétez tous les champs obligatoires.',
                            );
                            return;
                          }

                          final authUser = ref
                              .read(authControllerProvider)
                              .value;

                          setDialogState(() => savingDialog = true);
                          try {
                            final response = await ref
                                .read(dioProvider)
                                .post(
                                  '/auth/register/',
                                  data: {
                                    'username': username,
                                    'first_name': firstName,
                                    'last_name': lastName,
                                    'email': email,
                                    'phone': phone,
                                    'password': password,
                                    'role': 'teacher',
                                    if (authUser?.etablissementId != null)
                                      'etablissement':
                                          authUser!.etablissementId,
                                  },
                                );
                            final payload = response.data;
                            if (payload is Map<String, dynamic>) {
                              createdUserId = _asInt(payload['id']);
                            }

                            // Un echec du televersement ne doit pas annuler
                            // la creation: le compte existe, la photo se
                            // rajoute ensuite depuis l'edition.
                            if (createdUserId != null && photoBytes != null) {
                              await _uploadTeacherPhoto(
                                createdUserId!,
                                bytes: photoBytes,
                                path: photoPath,
                                fileName: photoFileName,
                              );
                            }
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                            }
                          } catch (error) {
                            _showMessage('Erreur création compte: $error');
                            if (context.mounted) {
                              setDialogState(() => savingDialog = false);
                            }
                          }
                        },
                  child: const Text('Créer compte'),
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
    passwordController.dispose();

    if (created == true) {
      await _loadData();
      if (!mounted) {
        return true;
      }
      _showMessage('Compte enseignant créé.', isSuccess: true);

      var targetUserId = (createdUserId != null && createdUserId! > 0)
          ? createdUserId
          : null;

      if (targetUserId == null) {
        final createdUser = _teacherUsers.firstWhere(
          (u) =>
              (u['username'] ?? '').toString().trim().toLowerCase() ==
              createdUsername,
          orElse: () => <String, dynamic>{},
        );
        final fallbackId = _asInt(createdUser['id']);
        if (fallbackId > 0) {
          targetUserId = fallbackId;
        }
      }

      final createProfileNow = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Créer le profil maintenant ?'),
            content: const Text(
              'Le compte enseignant est créé. Voulez-vous ouvrir directement la création du profil enseignant ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Plus tard'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Créer profil'),
              ),
            ],
          );
        },
      );

      if (createProfileNow == true) {
        await _openCreateProfileDialog(preferredUserId: targetUserId);
      }
      return true;
    }
    return false;
  }
}
