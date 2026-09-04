part of 'students_page.dart';

/// Le formulaire de modification d'un dossier élève.
///
/// Il se lit et se corrige seul: le mêler à l'inscription obligeait à
/// parcourir les deux pour n'en changer qu'un.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit les
/// champs de la page comme avant.
extension _FormulaireDeProfil on _StudentsPageState {
  Future<void> _openProfileForm() {
    final student = _selectedStudent;
    if (student == null) {
      _showMessage('Sélectionne un élève.');
      return Future.value();
    }

    _prepareProfileForm(student);

    return _openFloatingPanel(
      title: 'Modifier dossier élève',
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
                controller: _updateFirstNameController,
                decoration: const InputDecoration(labelText: 'Prénom *'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _updateLastNameController,
                decoration: const InputDecoration(labelText: 'Nom *'),
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _updateEmailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _updatePhoneController,
                decoration: const InputDecoration(labelText: 'Téléphone'),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate:
                      _updateBirthDate ??
                      student.birthDate ??
                      DateTime(2010, 1, 1),
                  firstDate: DateTime(1980),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _updateBirthDate = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.cake_outlined),
              label: Text(
                _updateBirthDate == null
                    ? 'Date naissance'
                    : _apiDate(_updateBirthDate!),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate:
                      _updateEnrollmentDate ??
                      student.enrollmentDate ??
                      DateTime.now(),
                  firstDate: DateTime(DateTime.now().year - 15),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _updateEnrollmentDate = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.event_available_outlined),
              label: Text(
                _updateEnrollmentDate == null
                    ? "Date d'inscription"
                    : 'Inscrit(e) le ${_apiDate(_updateEnrollmentDate!)}',
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _updateGender,
                decoration: const InputDecoration(labelText: 'Genre'),
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
                  _updateGender = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: _selectedClassroomUpdateId,
                decoration: const InputDecoration(
                  labelText: 'Réattribuer classe',
                ),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _selectedClassroomUpdateId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: _selectedParentUpdateId,
                decoration: const InputDecoration(labelText: 'Parent lié'),
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
                  _selectedParentUpdateId = value;
                  refreshPanel();
                },
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _saveStudentAssignments,
                      successMessage: 'Dossier élève mis à jour.',
                    ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer dossier'),
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
                            await _pickProfilePhoto(forRegistration: false);
                            refreshPanel();
                          },
                    icon: const Icon(Icons.person_outlined),
                    label: Text(
                      _updatePhotoFileName == null
                          ? 'Uploader nouvelle photo profil'
                          : 'Changer nouvelle photo profil',
                    ),
                  ),
                  if (_updatePhotoFileName != null)
                    Chip(
                      label: Text(
                        _updatePhotoFileName!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_updatePhotoFileName != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () {
                              _clearUpdateProfilePhotoSelection();
                              refreshPanel();
                            },
                      child: const Text('Retirer'),
                    ),
                  if (_updatePhotoFileName == null &&
                      student.photo.trim().isNotEmpty)
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _viewProfilePhoto(student.photo),
                      icon: const Icon(Icons.remove_red_eye_outlined),
                      label: const Text('Voir photo actuelle'),
                    ),
                ],
              ),
            ),
            if (_updatePhotoBytes != null && _updatePhotoBytes!.isNotEmpty)
              SizedBox(
                width: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aperçu nouvelle photo profil',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _previewMemoryImage(
                        _updatePhotoBytes!,
                        title: 'Nouvelle photo de profil',
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
                            _updatePhotoBytes!,
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
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _updateStudentPhoto,
                      successMessage: 'Photo élève mise à jour.',
                    ),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Uploader photo'),
            ),
          ],
        );
      },
    );
  }
}
