part of 'students_page.dart';

/// L'inscription d'un nouvel élève.
///
/// Le geste qui ouvre un dossier, distinct de celui qui le corrige.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit les
/// champs de la page comme avant.
extension _FormulaireDInscription on _StudentsPageState {
  Future<void> _openRegistrationForm() {
    return _openFloatingPanel(
      title: 'Inscription d\'un élève',
      contentBuilder: (panelContext, refreshPanel) {
        final isCompactPreview = MediaQuery.of(panelContext).size.width < 720;
        final profilePreviewHeight = isCompactPreview ? 120.0 : 160.0;
        final profilePreviewWidth = isCompactPreview ? 160.0 : 220.0;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Username *'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'Prénom *'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Nom *'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe *',
                  helperText: 'Minimum 8 caractères',
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Téléphone'),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _registrationGender,
                decoration: const InputDecoration(labelText: 'Genre *'),
                items: const [
                  DropdownMenuItem<String>(
                    value: 'M',
                    child: Text('Masculin'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'F',
                    child: Text('Féminin'),
                  ),
                ],
                onChanged: (value) {
                  _registrationGender = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _registrationClassroomId,
                decoration: const InputDecoration(labelText: 'Classe *'),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _registrationClassroomId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: _registrationParentId,
                decoration: const InputDecoration(
                  labelText: 'Parent (optionnel)',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Aucun parent'),
                  ),
                  ..._parents.map(
                    (row) => DropdownMenuItem<int?>(
                      value: _asInt(row['id']),
                      child: Text(_parentLabel(row)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  _registrationParentId = value;
                  refreshPanel();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate: _birthDate ?? DateTime(2010, 1, 1),
                  firstDate: DateTime(1980),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _birthDate = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.cake_outlined),
              label: Text(
                _birthDate == null ? 'Date naissance' : _apiDate(_birthDate!),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate: _enrollmentDate ?? DateTime.now(),
                  // Une inscription anterieure a la rentree precedente releve
                  // de la reprise d'historique, pas de la saisie courante.
                  firstDate: DateTime(DateTime.now().year - 15),
                  // Postdater fausserait les effectifs de l'annee en cours; le
                  // serveur le refuse, autant ne pas le proposer.
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _enrollmentDate = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.event_available_outlined),
              label: Text(
                _enrollmentDate == null
                    ? "Inscrit(e) aujourd'hui"
                    : 'Inscrit(e) le ${_apiDate(_enrollmentDate!)}',
              ),
            ),
            SizedBox(
              width: 560,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            await _pickProfilePhoto(forRegistration: true);
                            refreshPanel();
                          },
                    icon: const Icon(Icons.person_outlined),
                    label: Text(
                      _registrationPhotoFileName == null
                          ? 'Uploader photo de profil'
                          : 'Changer photo de profil',
                    ),
                  ),
                  if (_registrationPhotoFileName != null)
                    Chip(
                      label: Text(
                        _registrationPhotoFileName!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_registrationPhotoFileName != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () {
                              _clearRegistrationPhotoSelection();
                              refreshPanel();
                            },
                      child: const Text('Retirer'),
                    ),
                ],
              ),
            ),
            if (_registrationPhotoBytes != null &&
                _registrationPhotoBytes!.isNotEmpty)
              SizedBox(
                width: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aperçu photo de profil',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _previewMemoryImage(
                        _registrationPhotoBytes!,
                        title: 'Photo de profil (inscription)',
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight: profilePreviewHeight,
                            maxWidth: profilePreviewWidth,
                          ),
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: Image.memory(
                            _registrationPhotoBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Padding(
                                padding: EdgeInsets.all(10),
                                child: Text('Aperçu indisponible.'),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _registerStudent,
                      successMessage: 'Élève inscrit avec succès.',
                      afterSuccess: _offerRegistrationPaymentFlow,
                    ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Inscrire élève'),
            ),
          ],
        );
      },
    );
  }
}
