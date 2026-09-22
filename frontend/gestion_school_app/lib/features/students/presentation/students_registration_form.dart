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
            _blocFamille(panelContext, refreshPanel),
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

  /// La famille de l'élève, obligatoire depuis cette version.
  ///
  /// Un élève sans famille joignable est un dossier qu'on ne peut ni
  /// relancer ni prévenir. Le bloc cherche d'abord si le parent est déjà
  /// enregistré: sans cela, trois frères inscrits séparément donnaient trois
  /// comptes parents, et le père recevait trois accès pour ses trois enfants.
  Widget _blocFamille(BuildContext panelContext, VoidCallback refreshPanel) {
    final scheme = Theme.of(panelContext).colorScheme;
    final textTheme = Theme.of(panelContext).textTheme;
    final rattache = _registrationParentId != null;

    return SizedBox(
      width: 700,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.family_restroom, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Parent ou tuteur *', style: textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                    key: const Key('inscription-parent-telephone'),
                    controller: _parentPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone du parent *',
                      helperText: 'Sert à retrouver une famille déjà inscrite',
                    ),
                    onChanged: (_) => refreshPanel(),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('inscription-chercher-parent'),
                  onPressed: _rechercheParentEnCours
                      ? null
                      : () async {
                          await _chercherLeParent();
                          refreshPanel();
                        },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Ce parent est-il déjà inscrit ?'),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    key: const Key('inscription-lien-parente'),
                    isExpanded: true,
                    initialValue: _lienParente,
                    decoration: const InputDecoration(
                      labelText: 'Lien avec l\'élève *',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pere', child: Text('Père')),
                      DropdownMenuItem(value: 'mere', child: Text('Mère')),
                      DropdownMenuItem(value: 'tuteur', child: Text('Tuteur')),
                    ],
                    onChanged: (valeur) {
                      _lienParente = valeur;
                      refreshPanel();
                    },
                  ),
                ),
              ],
            ),
            if (_parentsTrouves.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Déjà enregistré — rattachez plutôt que de créer un doublon :',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              ..._parentsTrouves.map(
                (parent) => RadioListTile<int?>(
                  key: Key('parent-trouve-${parent['id']}'),
                  value: (parent['id'] as num?)?.toInt(),
                  // ignore: deprecated_member_use
                  groupValue: _registrationParentId,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${parent['nom']} — ${parent['telephone']}'),
                  subtitle: Text(
                    '${parent['enfants']} enfant(s) déjà rattaché(s)',
                    style: textTheme.bodySmall,
                  ),
                  // ignore: deprecated_member_use
                  onChanged: (valeur) {
                    _registrationParentId = valeur;
                    refreshPanel();
                  },
                ),
              ),
              if (rattache)
                TextButton(
                  onPressed: () {
                    _registrationParentId = null;
                    refreshPanel();
                  },
                  child: const Text('Non, c\'est une autre famille'),
                ),
            ],
            if (!rattache) ...[
              const SizedBox(height: 12),
              Text('Nouveau parent', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _parentFirstNameController,
                      decoration: const InputDecoration(
                        labelText: 'Prénom du parent',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      key: const Key('inscription-parent-nom'),
                      controller: _parentLastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom du parent *',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _parentWhatsappController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Numéro WhatsApp',
                        helperText: 'Recevra les bulletins',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _parentEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Email du parent',
                      ),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                key: const Key('inscription-consentement-whatsapp'),
                value: _parentWhatsappConsent,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Le parent accepte de recevoir les bulletins par WhatsApp',
                ),
                subtitle: Text(
                  // Le bulletin d'un mineur passe par un service tiers: son
                  // accord se demande avant, en sa présence, pas après.
                  'À cocher devant lui. Sans son accord, aucun envoi n\'est préparé.',
                  style: textTheme.bodySmall,
                ),
                onChanged: (valeur) {
                  _parentWhatsappConsent = valeur ?? false;
                  refreshPanel();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _chercherLeParent() async {
    final telephone = _parentPhoneController.text.trim();
    if (telephone.isEmpty) {
      _showMessage('Saisissez le téléphone du parent pour le rechercher.');
      return;
    }

    majEtat(() => _rechercheParentEnCours = true);
    try {
      final trouves = await ref
          .read(studentsRepositoryProvider)
          .chercherDesParents(telephone: telephone);
      majEtat(() => _parentsTrouves = trouves);
      if (trouves.isEmpty) {
        _showMessage(
          'Aucune famille enregistrée avec ce numéro. Créez le parent.',
        );
      }
    } catch (error) {
      _showMessage(_extractErrorMessage(error));
    } finally {
      majEtat(() => _rechercheParentEnCours = false);
    }
  }
}
