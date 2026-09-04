part of 'students_page.dart';

/// La fiche complète d'un élève, sortie de l'écran qui l'ouvre.
///
/// Quatre cent soixante lignes: le dossier réunit historique, discipline,
/// absences et frais, et sa mise en page occupait à elle seule un dixième du
/// fichier.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit les
/// champs de la page comme avant.
extension _PanneauDossierComplet on _StudentsPageState {
  Future<void> _openStudentFullDetailsPanel(Student student) async {
    if (!mounted) {
      return;
    }

    majEtat(() {
      _selectedStudent = student;
      _selectedClassroomUpdateId = student.classroomId;
      _selectedParentUpdateId = student.parentId;
    });

    await _loadStudentLinkedData(student.id);
    if (!mounted) {
      return;
    }

    await _openFloatingPanel(
      title: 'Fiche élève complète',
      contentBuilder: (panelContext, refreshPanel) {
        final selected = _selectedStudent;
        if (selected == null || selected.id != student.id) {
          return const Text('Aucune donnée élève disponible.');
        }
        final photoPath = selected.photo.trim();
        final hasPhoto = photoPath.isNotEmpty;
        final photoUrl = hasPhoto ? _resolveMediaUrl(photoPath) : '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.person_outline, size: 16),
                  label: Text(selected.fullName),
                ),
                Chip(
                  avatar: const Icon(Icons.badge_outlined, size: 16),
                  label: Text(selected.matricule),
                ),
                _statusBadge(
                  selected.isArchived ? 'Archivé' : 'Actif',
                  selected.isArchived,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Ce panneau ne montre que quatre rubriques; la vue 360 en couvre
            // onze (notes, examens, bibliotheque, cantine, passage...).
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(panelContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          StudentLookupPage(initialStudentId: selected.id),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_full, size: 18),
                label: const Text('Voir le dossier complet'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: hasPhoto ? () => _viewProfilePhoto(photoPath) : null,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: hasPhoto
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                );
                              },
                            )
                          : const Center(
                              child: Icon(
                                Icons.account_circle_outlined,
                                size: 36,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasPhoto
                            ? 'Photo de l\'élève (clique pour agrandir)'
                            : 'Photo de l\'élève non disponible',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      if (hasPhoto)
                        OutlinedButton.icon(
                          onPressed: () => _viewProfilePhoto(photoPath),
                          icon: const Icon(Icons.open_in_full_outlined),
                          label: const Text('Afficher en grand'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _studentInfoPill(
                  icon: Icons.class_outlined,
                  label: 'Classe',
                  value: selected.classroomName.isEmpty
                      ? 'Non attribuée'
                      : selected.classroomName,
                ),
                _studentInfoPill(
                  icon: Icons.family_restroom_outlined,
                  label: 'Parent',
                  value: selected.parentName.isEmpty
                      ? 'Non attribué'
                      : selected.parentName,
                ),
                _studentInfoPill(
                  icon: Icons.cake_outlined,
                  label: 'Naissance',
                  value: selected.birthDate == null
                      ? 'Non renseignée'
                      : _apiDate(selected.birthDate!),
                ),
                if (selected.phone.trim().isNotEmpty)
                  _studentInfoPill(
                    icon: Icons.phone_outlined,
                    label: 'Téléphone',
                    value: selected.phone,
                  ),
                if (selected.email.trim().isNotEmpty)
                  _studentInfoPill(
                    icon: Icons.alternate_email_outlined,
                    label: 'Email',
                    value: selected.email,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actions dossier',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _saving ? null : _openProfileForm,
                        icon: const Icon(Icons.edit_note_outlined),
                        label: const Text('Gérer dossier'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _saving
                            ? null
                            : () => _toggleArchive(selected),
                        icon: Icon(
                          selected.isArchived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                        ),
                        label: Text(
                          selected.isArchived ? 'Réactiver' : 'Archiver',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                await showModalBottomSheet<void>(
                                  context: context,
                                  builder: (sheetContext) {
                                    return SafeArea(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ListTile(
                                            leading: const Icon(
                                              Icons.badge_outlined,
                                            ),
                                            title: const Text('Imprimer carte'),
                                            onTap: () async {
                                              Navigator.of(sheetContext).pop();
                                              final success =
                                                  await _printStudentCard();
                                              if (success) {
                                                _showMessage(
                                                  'Carte élève prête à l\'impression.',
                                                  isSuccess: true,
                                                );
                                              }
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.visibility_outlined,
                                            ),
                                            title: const Text('Aperçu carte'),
                                            onTap: () async {
                                              Navigator.of(sheetContext).pop();
                                              final success =
                                                  await _quickPreviewStudentCard();
                                              if (success) {
                                                _showMessage(
                                                  'Aperçu rapide affiché.',
                                                  isSuccess: true,
                                                );
                                              }
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                              Icons.picture_as_pdf_outlined,
                                            ),
                                            title: const Text(
                                              'Exporter carte PDF',
                                            ),
                                            onTap: () async {
                                              Navigator.of(sheetContext).pop();
                                              final success =
                                                  await _exportStudentCardPdf();
                                              if (success) {
                                                _showMessage(
                                                  'Carte élève exportée en PDF.',
                                                  isSuccess: true,
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                        icon: const Icon(Icons.credit_card_outlined),
                        label: const Text('Carte élève'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_detailLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metricChip('Historique académique', '${_history.length}'),
                  _metricChip(
                    'Incidents ouverts',
                    '${_incidents.where((i) => (i['status']?.toString() ?? '') != 'resolved').length}',
                  ),
                  _metricChip(
                    'Absences',
                    '${_attendances.where((a) => a['is_absent'] == true).length}',
                  ),
                  _metricChip(
                    'Retards',
                    '${_attendances.where((a) => a['is_late'] == true).length}',
                  ),
                  _metricChip(
                    'Solde frais',
                    _money(
                      _fees.fold<double>(
                        0,
                        (sum, row) => sum + _toDouble(row['balance']),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _dossierSectionCard(
                title: 'Historique académique (${_history.length})',
                children: _history.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Text('Aucun historique disponible.'),
                        ),
                      ]
                    : _history
                          .map(
                            (row) => ListTile(
                              dense: true,
                              title: Text(
                                'Année: ${_yearName(_asInt(row['academic_year']))} • Classe: ${_classroomName(_asInt(row['classroom']))}',
                              ),
                              subtitle: Text(
                                'Moyenne: ${row['average'] ?? '-'} • Rang: ${row['rank'] ?? '-'}',
                              ),
                            ),
                          )
                          .toList(),
              ),
              _dossierSectionCard(
                title: 'Dossier disciplinaire (${_incidents.length})',
                children: _incidents.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Text('Aucun incident disciplinaire.'),
                        ),
                      ]
                    : _incidents.take(20).map((row) {
                        final isResolved =
                            (row['status'] ?? '').toString() == 'resolved';
                        return ListTile(
                          dense: true,
                          title: Text(
                            '${row['category'] ?? 'Incident'} • ${row['incident_date'] ?? ''}',
                          ),
                          subtitle: Text(
                            '${row['description'] ?? ''}\nStatut: ${isResolved ? 'Traité' : 'Ouvert'} • Gravité: ${_severityLabel((row['severity'] ?? '').toString())}',
                          ),
                          isThreeLine: true,
                        );
                      }).toList(),
              ),
              _dossierSectionCard(
                title: 'Absences & retards (${_attendances.length})',
                children: _attendances.isEmpty
                    ? const [
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Text('Aucune donnée de présence.'),
                        ),
                      ]
                    : _attendances.take(25).map((row) {
                        final proofPath = (row['proof'] ?? '')
                            .toString()
                            .trim();
                        final hasProof = proofPath.isNotEmpty;
                        return ListTile(
                          dense: true,
                          title: Text('${row['date'] ?? ''}'),
                          subtitle: Text(
                            'Absent: ${row['is_absent'] == true ? 'Oui' : 'Non'} • Retard: ${row['is_late'] == true ? 'Oui' : 'Non'} • Justificatif: ${hasProof ? 'Oui' : 'Non'}',
                          ),
                          trailing: hasProof
                              ? IconButton(
                                  tooltip: 'Voir justificatif',
                                  icon: const Icon(Icons.image_outlined),
                                  onPressed: () =>
                                      _viewAttendanceProof(proofPath),
                                )
                              : null,
                        );
                      }).toList(),
              ),
              _dossierSectionCard(
                title:
                    'Frais & paiements (${_fees.length} frais / ${_payments.length} paiements)',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Total dû: ${_money(_fees.fold<double>(0, (sum, row) => sum + _toDouble(row['amount_due'])))} • '
                      'Total payé: ${_money(_fees.fold<double>(0, (sum, row) => sum + _toDouble(row['amount_paid'])))} • '
                      'Solde: ${_money(_fees.fold<double>(0, (sum, row) => sum + _toDouble(row['balance'])))}',
                    ),
                  ),
                  if (_fees.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text('Aucun frais scolaire enregistré.'),
                    )
                  else
                    ..._fees
                        .take(20)
                        .map(
                          (row) => ListTile(
                            dense: true,
                            title: Text(
                              '${_feeTypeLabel((row['fee_type'] ?? '').toString())} • Échéance ${row['due_date'] ?? ''}',
                            ),
                            subtitle: Text(
                              'Dû: ${_money(_toDouble(row['amount_due']))} • Payé: ${_money(_toDouble(row['amount_paid']))} • Solde: ${_money(_toDouble(row['balance']))}',
                            ),
                          ),
                        ),
                  if (_payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text('Aucun paiement enregistré.'),
                    )
                  else
                    ..._payments
                        .take(15)
                        .map(
                          (row) => ListTile(
                            dense: true,
                            title: Text(
                              '${_money(_toDouble(row['amount']))} • ${row['method'] ?? 'N/A'}',
                            ),
                            subtitle: Text(
                              'Référence: ${row['reference'] ?? '-'} • Date: ${row['created_at'] ?? ''}',
                            ),
                          ),
                        ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
