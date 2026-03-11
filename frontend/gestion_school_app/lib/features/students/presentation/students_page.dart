import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../domain/student.dart';
import 'students_controller.dart';

class StudentsPage extends ConsumerStatefulWidget {
  const StudentsPage({super.key});

  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  static const List<int> _tableRowsPerPageOptions = [10, 15, 25, 50];
  int _tableRowsPerPage = 15;
  int _tablePage = 1;

  final _usernameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _updateFirstNameController = TextEditingController();
  final _updateLastNameController = TextEditingController();
  final _updateEmailController = TextEditingController();
  final _updatePhoneController = TextEditingController();
  final _historyAverageController = TextEditingController();
  final _historyRankController = TextEditingController();
  final _incidentCategoryController = TextEditingController();
  final _incidentDescriptionController = TextEditingController();
  final _incidentSanctionController = TextEditingController();
  final _attendanceReasonController = TextEditingController();
  final _feeAmountDueController = TextEditingController();
  final _paymentAmountController = TextEditingController();
  final _paymentMethodController = TextEditingController(text: 'Espèces');
  final _paymentReferenceController = TextEditingController();

  String? _attendanceProofPath;
  Uint8List? _attendanceProofBytes;
  String? _attendanceProofFileName;

  String? _registrationPhotoPath;
  Uint8List? _registrationPhotoBytes;
  String? _registrationPhotoFileName;

  String? _updatePhotoPath;
  Uint8List? _updatePhotoBytes;
  String? _updatePhotoFileName;

  bool _loading = true;
  bool _saving = false;
  bool _detailLoading = false;

  List<Student> _students = [];
  List<Student> _filteredStudents = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _parents = [];
  List<Map<String, dynamic>> _years = [];

  String _statusFilter = 'active';
  int? _classFilterId;
  int? _cardsClassroomId;
  String _cardsLayoutMode = 'a4_6up';
  String _sortBy = 'name';
  bool _sortAscending = true;

  int? _registrationClassroomId;
  int? _registrationParentId;
  DateTime? _birthDate;
  int? _historyYearId;
  int? _historyClassroomId;

  DateTime _incidentDate = DateTime.now();
  String _incidentSeverity = 'medium';
  bool _incidentParentNotified = false;

  DateTime _attendanceDate = DateTime.now();
  bool _attendanceAbsent = false;
  bool _attendanceLate = false;

  int? _feeAcademicYearId;
  String _feeType = 'registration';
  DateTime _feeDueDate = DateTime.now();
  int? _paymentFeeId;

  Student? _selectedStudent;
  int? _selectedClassroomUpdateId;
  int? _selectedParentUpdateId;
  DateTime? _updateBirthDate;

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _incidents = [];
  List<Map<String, dynamic>> _attendances = [];
  List<Map<String, dynamic>> _fees = [];
  List<Map<String, dynamic>> _payments = [];

  @override
  void initState() {
    super.initState();
    _loadBaseData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _updateFirstNameController.dispose();
    _updateLastNameController.dispose();
    _updateEmailController.dispose();
    _updatePhoneController.dispose();
    _historyAverageController.dispose();
    _historyRankController.dispose();
    _incidentCategoryController.dispose();
    _incidentDescriptionController.dispose();
    _incidentSanctionController.dispose();
    _attendanceReasonController.dispose();
    _feeAmountDueController.dispose();
    _paymentAmountController.dispose();
    _paymentMethodController.dispose();
    _paymentReferenceController.dispose();
    super.dispose();
  }

  Future<void> _loadBaseData({int? keepSelectedId}) async {
    setState(() => _loading = true);
    try {
      final repository = ref.read(studentsRepositoryProvider);
      final results = await Future.wait([
        repository.fetchStudents(),
        repository.fetchClassrooms(),
        repository.fetchParents(),
        repository.fetchAcademicYears(),
      ]);

      if (!mounted) return;
      setState(() {
        _students = results[0] as List<Student>;
        _classrooms = results[1] as List<Map<String, dynamic>>;
        _parents = results[2] as List<Map<String, dynamic>>;
        _years = results[3] as List<Map<String, dynamic>>;
        _registrationClassroomId ??= _classrooms.isNotEmpty
            ? _asInt(_classrooms.first['id'])
            : null;
        _cardsClassroomId ??= _classrooms.isNotEmpty
            ? _asInt(_classrooms.first['id'])
            : null;
        _historyYearId ??= _years.isNotEmpty
            ? _asInt(_years.first['id'])
            : null;
        _feeAcademicYearId ??= _years.isNotEmpty
            ? _asInt(_years.first['id'])
            : null;
      });

      _applyFilters(preferredStudentId: keepSelectedId ?? _selectedStudent?.id);
    } catch (error) {
      _showMessage('Erreur chargement élèves: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters({
    int? preferredStudentId,
    bool resetVisibleCount = false,
  }) {
    final search = _searchController.text.trim().toLowerCase();
    final filtered = _students.where((student) {
      if (_statusFilter == 'active' && student.isArchived) return false;
      if (_statusFilter == 'archived' && !student.isArchived) return false;
      if (_classFilterId != null && student.classroomId != _classFilterId) {
        return false;
      }
      if (search.isEmpty) return true;
      final haystack =
          '${student.fullName} ${student.matricule} ${student.classroomName} ${student.parentName}'
              .toLowerCase();
      return haystack.contains(search);
    }).toList();

    filtered.sort(_compareStudents);

    final beforeId = _selectedStudent?.id;
    Student? nextSelected = _selectedStudent;

    if (preferredStudentId != null) {
      for (final student in filtered) {
        if (student.id == preferredStudentId) {
          nextSelected = student;
          break;
        }
      }
    }

    if (nextSelected != null &&
        !filtered.any((s) => s.id == nextSelected!.id)) {
      nextSelected = filtered.isNotEmpty ? filtered.first : null;
    }
    if (nextSelected == null && filtered.isNotEmpty) {
      nextSelected = filtered.first;
    }
    final selectedClassroomId = nextSelected?.classroomId;
    final totalPages = filtered.isEmpty
        ? 1
        : ((filtered.length + _tableRowsPerPage - 1) ~/ _tableRowsPerPage);
    var nextTablePage = resetVisibleCount ? 1 : _tablePage;
    if (nextTablePage < 1) {
      nextTablePage = 1;
    }
    if (nextSelected != null) {
      final selectedIndex = filtered.indexWhere(
        (s) => s.id == nextSelected!.id,
      );
      if (selectedIndex >= 0) {
        final selectedPage = (selectedIndex ~/ _tableRowsPerPage) + 1;
        if (resetVisibleCount) {
          nextTablePage = selectedPage;
        }
      }
    }
    if (nextTablePage > totalPages) {
      nextTablePage = totalPages;
    }

    setState(() {
      _filteredStudents = filtered;
      _selectedStudent = nextSelected;
      _tablePage = nextTablePage;
      _selectedClassroomUpdateId = nextSelected?.classroomId;
      _selectedParentUpdateId = nextSelected?.parentId;
      if (selectedClassroomId != null &&
          (_historyClassroomId == null || beforeId != nextSelected?.id)) {
        _historyClassroomId = selectedClassroomId;
      }
      if (nextSelected == null) {
        _history = [];
        _incidents = [];
        _attendances = [];
        _fees = [];
        _payments = [];
      }
    });

    if (nextSelected != null && nextSelected.id != beforeId) {
      _loadStudentLinkedData(nextSelected.id);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _applyFilters(resetVisibleCount: true);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _applyFilters(resetVisibleCount: true);
  }

  void _resetStudentsFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _classFilterId = null;
      _statusFilter = 'all';
      _sortBy = 'name';
      _sortAscending = true;
      _tablePage = 1;
    });
    _applyFilters(resetVisibleCount: true);
  }

  Future<void> _pickProfilePhoto({required bool forRegistration}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final selectedPath = file.path?.trim().isEmpty ?? true ? null : file.path;
      final selectedBytes = file.bytes;
      final selectedFileName = file.name.trim().isEmpty ? null : file.name;

      if (forRegistration) {
        _registrationPhotoPath = selectedPath;
        _registrationPhotoBytes = selectedBytes;
        _registrationPhotoFileName = selectedFileName;
      } else {
        _updatePhotoPath = selectedPath;
        _updatePhotoBytes = selectedBytes;
        _updatePhotoFileName = selectedFileName;
      }

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _showMessage('Erreur sélection photo profil: $error');
    }
  }

  void _clearRegistrationPhotoSelection() {
    _registrationPhotoPath = null;
    _registrationPhotoBytes = null;
    _registrationPhotoFileName = null;
    if (mounted) {
      setState(() {});
    }
  }

  void _clearUpdateProfilePhotoSelection() {
    _updatePhotoPath = null;
    _updatePhotoBytes = null;
    _updatePhotoFileName = null;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickAttendanceProof() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      _attendanceProofPath = file.path?.trim().isEmpty ?? true
          ? null
          : file.path;
      _attendanceProofBytes = file.bytes;
      _attendanceProofFileName = file.name.trim().isEmpty ? null : file.name;
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _showMessage('Erreur sélection justificatif: $error');
    }
  }

  void _clearAttendanceProof() {
    _attendanceProofPath = null;
    _attendanceProofBytes = null;
    _attendanceProofFileName = null;
    if (mounted) {
      setState(() {});
    }
  }

  void _prepareProfileForm(Student student) {
    _selectedClassroomUpdateId = student.classroomId;
    _selectedParentUpdateId = student.parentId;
    _updateBirthDate = student.birthDate;
    _clearUpdateProfilePhotoSelection();
    _updateFirstNameController.text = student.firstName;
    _updateLastNameController.text = student.lastName;
    _updateEmailController.text = student.email;
    _updatePhoneController.text = student.phone;
  }

  Future<void> _loadStudentLinkedData(int studentId) async {
    setState(() => _detailLoading = true);
    try {
      final repository = ref.read(studentsRepositoryProvider);
      final results = await Future.wait([
        repository.fetchStudentHistory(studentId),
        repository.fetchStudentDiscipline(studentId),
        repository.fetchStudentAttendances(studentId),
        repository.fetchStudentFees(studentId),
        repository.fetchStudentPayments(studentId),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0];
        _incidents = results[1];
        _attendances = results[2];
        _fees = results[3];
        _payments = results[4];
        final remainingFee = _fees.firstWhere(
          (row) => _toDouble(row['balance']) > 0,
          orElse: () => _fees.isNotEmpty ? _fees.first : <String, dynamic>{},
        );
        _paymentFeeId = remainingFee.isNotEmpty
            ? _asInt(remainingFee['id'])
            : null;
      });
    } catch (error) {
      _showMessage('Erreur chargement dossier élève: $error');
    } finally {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  Future<bool> _registerStudent() async {
    final username = _usernameController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final password = _passwordController.text;
    final classroomId = _registrationClassroomId;

    if (username.isEmpty ||
        firstName.isEmpty ||
        lastName.isEmpty ||
        password.length < 8 ||
        classroomId == null) {
      await _showRegistrationFailure(
        'Complète username, prénom, nom, mot de passe (8+) et classe.',
      );
      return false;
    }

    setState(() => _saving = true);
    try {
      final student = await ref
          .read(studentsRepositoryProvider)
          .createStudentWithUser(
            username: username,
            firstName: firstName,
            lastName: lastName,
            password: password,
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            classroomId: classroomId,
            parentId: _registrationParentId,
            birthDate: _birthDate,
            photoPath: _registrationPhotoPath,
            photoBytes: _registrationPhotoBytes,
            photoFileName: _registrationPhotoFileName,
          );

      if (!mounted) return false;
      _usernameController.clear();
      _firstNameController.clear();
      _lastNameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _passwordController.clear();
      _clearRegistrationPhotoSelection();
      _birthDate = null;
      _registrationParentId = null;
      await _loadBaseData(keepSelectedId: student.id);
      return true;
    } catch (error) {
      await _showRegistrationFailure(_extractErrorMessage(error));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleArchive(Student student) async {
    final confirmed = await _confirmToggleArchive(student);
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(studentsRepositoryProvider)
          .toggleArchive(student.id, !student.isArchived);
      _showMessage(
        updated.isArchived
            ? 'Élève archivé avec succès.'
            : 'Élève réactivé avec succès.',
        isSuccess: true,
      );
      await _loadBaseData(keepSelectedId: student.id);
    } catch (error) {
      _showMessage('Erreur archivage élève: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmToggleArchive(Student student) async {
    if (!mounted) return false;

    final isReactivation = student.isArchived;
    final actionLabel = isReactivation ? 'Réactiver' : 'Archiver';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('$actionLabel élève'),
          content: Text(
            isReactivation
                ? 'Confirmer la réactivation de ${student.fullName} ?'
                : 'Confirmer l\'archivage de ${student.fullName} ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<bool> _saveStudentAssignments() async {
    final student = _selectedStudent;
    if (student == null) return false;

    final firstName = _updateFirstNameController.text.trim();
    final lastName = _updateLastNameController.text.trim();
    final email = _updateEmailController.text.trim();
    final phone = _updatePhoneController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      _showMessage('Prénom et nom sont obligatoires.');
      return false;
    }

    final hasUserChanges =
        firstName != student.firstName.trim() ||
        lastName != student.lastName.trim() ||
        email != student.email.trim() ||
        phone != student.phone.trim();
    final hasClassroomChanges =
        _selectedClassroomUpdateId != student.classroomId;
    final hasParentChanges = _selectedParentUpdateId != student.parentId;
    final hasBirthDateChanges =
        _apiDateOrEmpty(_updateBirthDate) != _apiDateOrEmpty(student.birthDate);

    if (!hasUserChanges &&
        !hasClassroomChanges &&
        !hasParentChanges &&
        !hasBirthDateChanges) {
      _showMessage('Aucune modification détectée.');
      return false;
    }

    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(studentsRepositoryProvider)
          .updateStudentProfile(
            studentId: student.id,
            userId: student.userId,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            classroomId: _selectedClassroomUpdateId,
            parentId: _selectedParentUpdateId,
            birthDate: _updateBirthDate,
          );
      await _loadBaseData(keepSelectedId: updated.id);
      return true;
    } catch (error) {
      _showMessage('Erreur mise à jour élève: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _updateStudentPhoto() async {
    final student = _selectedStudent;
    if (student == null) return false;

    final hasPath = (_updatePhotoPath ?? '').trim().isNotEmpty;
    final hasBytes = _updatePhotoBytes != null && _updatePhotoBytes!.isNotEmpty;
    if (!hasPath && !hasBytes) {
      _showMessage('Sélectionne une photo avant enregistrement.');
      return false;
    }

    setState(() => _saving = true);
    try {
      final updated = await ref
          .read(studentsRepositoryProvider)
          .updateStudentPhoto(
            student.id,
            photoPath: _updatePhotoPath,
            photoBytes: _updatePhotoBytes,
            photoFileName: _updatePhotoFileName,
          );
      _clearUpdateProfilePhotoSelection();
      await _loadBaseData(keepSelectedId: updated.id);
      return true;
    } catch (error) {
      _showMessage('Erreur mise à jour photo: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _createHistoryEntry() async {
    final student = _selectedStudent;
    final yearId = _historyYearId;
    final classroomId = _historyClassroomId;

    if (student == null || yearId == null || classroomId == null) {
      _showMessage('Sélectionne élève, année et classe pour l’historique.');
      return false;
    }

    final average = double.tryParse(
      _historyAverageController.text.trim().replaceAll(',', '.'),
    );
    final rank = int.tryParse(_historyRankController.text.trim());

    if (average == null || rank == null || rank <= 0) {
      _showMessage('Saisis une moyenne valide et un rang > 0.');
      return false;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(studentsRepositoryProvider)
          .createStudentHistory(
            studentId: student.id,
            academicYearId: yearId,
            classroomId: classroomId,
            average: average,
            rank: rank,
          );
      _historyAverageController.clear();
      _historyRankController.clear();
      await _loadStudentLinkedData(student.id);
      return true;
    } catch (error) {
      _showMessage('Erreur ajout historique: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _createDisciplineIncident() async {
    final student = _selectedStudent;
    if (student == null) return false;

    final category = _incidentCategoryController.text.trim();
    final description = _incidentDescriptionController.text.trim();
    if (category.isEmpty || description.isEmpty) {
      _showMessage('Catégorie et description sont obligatoires.');
      return false;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(studentsRepositoryProvider)
          .createDisciplineIncident(
            studentId: student.id,
            incidentDate: _incidentDate,
            category: category,
            description: description,
            severity: _incidentSeverity,
            sanction: _incidentSanctionController.text.trim(),
            parentNotified: _incidentParentNotified,
          );
      _incidentCategoryController.clear();
      _incidentDescriptionController.clear();
      _incidentSanctionController.clear();
      setState(() {
        _incidentSeverity = 'medium';
        _incidentParentNotified = false;
      });
      await _loadStudentLinkedData(student.id);
      return true;
    } catch (error) {
      _showMessage('Erreur dossier disciplinaire: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleIncidentStatus(Map<String, dynamic> incident) async {
    final student = _selectedStudent;
    if (student == null) return;

    final incidentId = _asInt(incident['id']);
    if (incidentId <= 0) {
      _showMessage('Incident invalide.');
      return;
    }

    final currentStatus = (incident['status'] ?? 'open').toString();
    final targetStatus = currentStatus == 'resolved' ? 'open' : 'resolved';

    setState(() => _saving = true);
    try {
      await ref
          .read(studentsRepositoryProvider)
          .updateDisciplineIncidentStatus(
            incidentId: incidentId,
            status: targetStatus,
          );
      await _loadStudentLinkedData(student.id);
      _showMessage(
        targetStatus == 'resolved'
            ? 'Incident marqué comme traité.'
            : 'Incident rouvert.',
        isSuccess: true,
      );
    } catch (error) {
      _showMessage('Erreur mise à jour incident: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _createAttendanceEntry() async {
    final student = _selectedStudent;
    if (student == null) return false;

    if (!_attendanceAbsent && !_attendanceLate) {
      _showMessage('Coche au moins Absence ou Retard.');
      return false;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(studentsRepositoryProvider)
          .createAttendance(
            studentId: student.id,
            date: _attendanceDate,
            isAbsent: _attendanceAbsent,
            isLate: _attendanceLate,
            reason: _attendanceReasonController.text.trim(),
            proofPath: _attendanceProofPath,
            proofBytes: _attendanceProofBytes,
            proofFileName: _attendanceProofFileName,
          );
      _attendanceReasonController.clear();
      _clearAttendanceProof();
      setState(() {
        _attendanceAbsent = false;
        _attendanceLate = false;
      });
      await _loadStudentLinkedData(student.id);
      return true;
    } catch (error) {
      _showMessage('Erreur enregistrement présence: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _createStudentFeeEntry() async {
    final student = _selectedStudent;
    final academicYearId = _feeAcademicYearId;
    if (student == null || academicYearId == null) {
      _showMessage('Sélectionne élève et année scolaire.');
      return false;
    }

    final amountDue = double.tryParse(
      _feeAmountDueController.text.trim().replaceAll(',', '.'),
    );
    if (amountDue == null || amountDue <= 0) {
      _showMessage('Montant du frais invalide.');
      return false;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(studentsRepositoryProvider)
          .createStudentFee(
            studentId: student.id,
            academicYearId: academicYearId,
            feeType: _feeType,
            amountDue: amountDue,
            dueDate: _feeDueDate,
          );
      _feeAmountDueController.clear();
      await _loadStudentLinkedData(student.id);
      return true;
    } catch (error) {
      _showMessage('Erreur création frais: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _createPaymentEntry() async {
    final student = _selectedStudent;
    final feeId = _paymentFeeId;
    if (student == null || feeId == null) {
      _showMessage('Sélectionne un frais à payer.');
      return false;
    }

    final amount = double.tryParse(
      _paymentAmountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      _showMessage('Montant du paiement invalide.');
      return false;
    }

    final method = _paymentMethodController.text.trim();
    if (method.isEmpty) {
      _showMessage('Renseigne la méthode de paiement.');
      return false;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(studentsRepositoryProvider)
          .createPayment(
            feeId: feeId,
            amount: amount,
            method: method,
            reference: _paymentReferenceController.text.trim(),
          );
      _paymentAmountController.clear();
      _paymentReferenceController.clear();
      await _loadStudentLinkedData(student.id);
      return true;
    } catch (error) {
      _showMessage('Erreur enregistrement paiement: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printPaymentReceipt(int paymentId) async {
    try {
      final bytes = await ref
          .read(studentsRepositoryProvider)
          .fetchReceiptPdf(paymentId);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      _showMessage('Erreur impression reçu: $error');
    }
  }

  String _classCardsExportFileName(int classroomId) {
    String className = 'classe';
    for (final row in _classrooms) {
      if (_asInt(row['id']) == classroomId) {
        className = (row['name'] ?? 'classe').toString();
        break;
      }
    }

    final classSlug = className.trim().replaceAll(RegExp(r'\s+'), '_');
    final suffix = _cardsLayoutMode == 'a4_6up'
        ? '_6parA4'
        : _cardsLayoutMode == 'a4_9up'
        ? '_9parA4'
        : '';
    return 'cartes_${classSlug.isEmpty ? 'classe' : classSlug}$suffix.pdf';
  }

  Future<bool> _printStudentCard() async {
    final student = _selectedStudent;
    if (student == null) {
      _showMessage('Sélectionne un élève.');
      return false;
    }

    try {
      final bytes = await ref
          .read(studentsRepositoryProvider)
          .fetchStudentCardPdf(student.id);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      return true;
    } catch (error) {
      _showMessage('Erreur impression carte élève: $error');
      return false;
    }
  }

  Future<bool> _quickPreviewStudentCard() async {
    final student = _selectedStudent;
    if (student == null) {
      _showMessage('Sélectionne un élève.');
      return false;
    }

    try {
      final bytes = await ref
          .read(studentsRepositoryProvider)
          .fetchStudentCardPdf(student.id);
      if (!mounted) return false;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Aperçu rapide: ${student.fullName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: PdfPreview(
                        build: (_) async => bytes,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                        useActions: false,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Fermer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      return true;
    } catch (error) {
      _showMessage('Erreur aperçu carte élève: $error');
      return false;
    }
  }

  Future<bool> _exportStudentCardPdf() async {
    final student = _selectedStudent;
    if (student == null) {
      _showMessage('Sélectionne un élève.');
      return false;
    }

    try {
      final bytes = await ref
          .read(studentsRepositoryProvider)
          .fetchStudentCardPdf(student.id);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'carte_eleve_${student.matricule}.pdf',
      );
      return true;
    } catch (error) {
      _showMessage('Erreur export carte élève: $error');
      return false;
    }
  }

  Future<bool> _printClassStudentCards() async {
    final classroomId = _cardsClassroomId;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionne une classe.');
      return false;
    }

    try {
      final bytes = await ref
          .read(studentsRepositoryProvider)
          .fetchClassStudentCardsPdf(classroomId, layoutMode: _cardsLayoutMode);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      return true;
    } catch (error) {
      _showMessage('Erreur impression cartes classe: $error');
      return false;
    }
  }

  Future<bool> _exportClassStudentCardsPdf() async {
    final classroomId = _cardsClassroomId;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionne une classe.');
      return false;
    }

    try {
      final bytes = await ref
          .read(studentsRepositoryProvider)
          .fetchClassStudentCardsPdf(classroomId, layoutMode: _cardsLayoutMode);
      await Printing.sharePdf(
        bytes: bytes,
        filename: _classCardsExportFileName(classroomId),
      );
      return true;
    } catch (error) {
      _showMessage('Erreur export cartes classe: $error');
      return false;
    }
  }

  Future<bool> _quickPreviewClassStudentCards() async {
    final classroomId = _cardsClassroomId;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionne une classe.');
      return false;
    }

    String className = 'Classe';
    for (final row in _classrooms) {
      if (_asInt(row['id']) == classroomId) {
        className = (row['name'] ?? 'Classe').toString();
        break;
      }
    }

    try {
      final bytes = await ref
          .read(studentsRepositoryProvider)
          .fetchClassStudentCardsPdf(classroomId, layoutMode: _cardsLayoutMode);
      if (!mounted) return false;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Aperçu rapide: cartes $className',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: PdfPreview(
                        build: (_) async => bytes,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                        useActions: false,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Fermer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      return true;
    } catch (error) {
      _showMessage('Erreur aperçu cartes classe: $error');
      return false;
    }
  }

  Future<void> _openClassCardsPanel() {
    _cardsClassroomId ??= _classFilterId;
    _cardsClassroomId ??= _classrooms.isNotEmpty
        ? _asInt(_classrooms.first['id'])
        : null;

    return _openFloatingPanel(
      title: 'Imprimer / Exporter cartes d’élèves',
      contentBuilder: (panelContext, refreshPanel) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<int?>(
                initialValue: _cardsClassroomId,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']} (ID ${row['id']})'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _cardsClassroomId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                initialValue: _cardsLayoutMode,
                decoration: const InputDecoration(labelText: 'Mode impression'),
                items: const [
                  DropdownMenuItem(
                    value: 'standard',
                    child: Text('Standard (1 carte / page)'),
                  ),
                  DropdownMenuItem(
                    value: 'a4_6up',
                    child: Text('A4 (6 cartes / page - conseillé)'),
                  ),
                ],
                onChanged: (value) {
                  _cardsLayoutMode = value ?? 'a4_6up';
                  refreshPanel();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      final success = await _quickPreviewClassStudentCards();
                      if (success) {
                        _showMessage('Aperçu rapide affiché.', isSuccess: true);
                      }
                    },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Aperçu rapide'),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _printClassStudentCards,
                      successMessage: _cardsLayoutMode == 'a4_6up'
                          ? 'Cartes élèves prêtes à l’impression (A4 - 6 cartes/page).'
                          : 'Cartes élèves générées.',
                    ),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Imprimer cartes'),
            ),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _exportClassStudentCardsPdf,
                      successMessage: _cardsLayoutMode == 'a4_6up'
                          ? 'PDF exporté (A4 - 6 cartes/page).'
                          : 'PDF exporté.',
                    ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exporter PDF'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFloatingPanel({
    required String title,
    required Widget Function(
      BuildContext panelContext,
      VoidCallback refreshPanel,
    )
    contentBuilder,
  }) async {
    final compact = MediaQuery.of(context).size.width < 920;

    if (compact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (panelContext, setPanelState) {
              void refreshPanel() {
                if (mounted) setState(() {});
                setPanelState(() {});
              }

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    16 + MediaQuery.of(panelContext).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        contentBuilder(panelContext, refreshPanel),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(panelContext).pop(),
                            child: const Text('Fermer'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (panelContext, setPanelState) {
            void refreshPanel() {
              if (mounted) setState(() {});
              setPanelState(() {});
            }

            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: contentBuilder(panelContext, refreshPanel),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(panelContext).pop(),
                          child: const Text('Fermer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitFromPanel({
    required BuildContext panelContext,
    required Future<bool> Function() action,
    required String successMessage,
  }) async {
    final success = await action();
    if (!success || !mounted) return;

    if (panelContext.mounted) {
      final navigator = Navigator.of(panelContext);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
    _showMessage(successMessage, isSuccess: true);
  }

  Future<void> _openHistoryForm() {
    return _openFloatingPanel(
      title: 'Ajouter historique académique',
      contentBuilder: (panelContext, refreshPanel) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                initialValue: _historyYearId,
                decoration: const InputDecoration(labelText: 'Année scolaire'),
                items: _years
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']} (ID ${row['id']})'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _historyYearId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                initialValue: _historyClassroomId,
                decoration: const InputDecoration(
                  labelText: 'Classe concernée',
                ),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']} (ID ${row['id']})'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _historyClassroomId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _historyAverageController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Moyenne'),
              ),
            ),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _historyRankController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rang'),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _createHistoryEntry,
                      successMessage: 'Historique académique ajouté.',
                    ),
              icon: const Icon(Icons.history_edu_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

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
              width: 260,
              child: DropdownButtonFormField<int>(
                initialValue: _registrationClassroomId,
                decoration: const InputDecoration(labelText: 'Classe *'),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']} (ID ${row['id']})'),
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
                    ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Inscrire élève'),
            ),
          ],
        );
      },
    );
  }

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
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedClassroomUpdateId,
                decoration: const InputDecoration(
                  labelText: 'Réattribuer classe',
                ),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']} (ID ${row['id']})'),
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

  Future<void> _openIncidentForm() {
    return _openFloatingPanel(
      title: 'Ajouter incident disciplinaire',
      contentBuilder: (panelContext, refreshPanel) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate: _incidentDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _incidentDate = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.event_outlined),
              label: Text(_apiDate(_incidentDate)),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _incidentCategoryController,
                decoration: const InputDecoration(labelText: 'Catégorie *'),
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _incidentDescriptionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description *'),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                initialValue: _incidentSeverity,
                decoration: const InputDecoration(labelText: 'Gravité'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Faible')),
                  DropdownMenuItem(value: 'medium', child: Text('Moyenne')),
                  DropdownMenuItem(value: 'high', child: Text('Élevée')),
                ],
                onChanged: (value) {
                  _incidentSeverity = value ?? 'medium';
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _incidentSanctionController,
                decoration: const InputDecoration(
                  labelText: 'Sanction (optionnel)',
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: Row(
                children: [
                  Checkbox(
                    value: _incidentParentNotified,
                    onChanged: (value) {
                      _incidentParentNotified = value ?? false;
                      refreshPanel();
                    },
                  ),
                  const Text('Parent notifié'),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _createDisciplineIncident,
                      successMessage: 'Incident disciplinaire enregistré.',
                    ),
              icon: const Icon(Icons.gavel_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAttendanceForm() {
    return _openFloatingPanel(
      title: 'Enregistrer absence / retard',
      contentBuilder: (panelContext, refreshPanel) {
        final isCompactProofPreview =
            MediaQuery.of(panelContext).size.width < 720;
        final proofPreviewHeight = isCompactProofPreview ? 120.0 : 160.0;
        final proofPreviewWidth = isCompactProofPreview ? 160.0 : 220.0;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate: _attendanceDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  _attendanceDate = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.event_available_outlined),
              label: Text(_apiDate(_attendanceDate)),
            ),
            SizedBox(
              width: 160,
              child: Row(
                children: [
                  Checkbox(
                    value: _attendanceAbsent,
                    onChanged: (value) {
                      _attendanceAbsent = value ?? false;
                      refreshPanel();
                    },
                  ),
                  const Text('Absence'),
                ],
              ),
            ),
            SizedBox(
              width: 160,
              child: Row(
                children: [
                  Checkbox(
                    value: _attendanceLate,
                    onChanged: (value) {
                      _attendanceLate = value ?? false;
                      refreshPanel();
                    },
                  ),
                  const Text('Retard'),
                ],
              ),
            ),
            SizedBox(
              width: 320,
              child: TextField(
                controller: _attendanceReasonController,
                decoration: const InputDecoration(
                  labelText: 'Motif (optionnel)',
                ),
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
                            await _pickAttendanceProof();
                            refreshPanel();
                          },
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: Text(
                      _attendanceProofFileName == null
                          ? 'Uploader photo justificatif'
                          : 'Changer photo justificatif',
                    ),
                  ),
                  if (_attendanceProofFileName != null)
                    Chip(
                      label: Text(
                        _attendanceProofFileName!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_attendanceProofFileName != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () {
                              _clearAttendanceProof();
                              refreshPanel();
                            },
                      child: const Text('Retirer'),
                    ),
                ],
              ),
            ),
            if (_attendanceProofBytes != null &&
                _attendanceProofBytes!.isNotEmpty)
              SizedBox(
                width: 560,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aperçu du justificatif',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _previewMemoryImage(
                        _attendanceProofBytes!,
                        title: 'Justificatif (absence/retard)',
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight: proofPreviewHeight,
                            maxWidth: proofPreviewWidth,
                          ),
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: Image.memory(
                            _attendanceProofBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Padding(
                                padding: EdgeInsets.all(10),
                                child: Text(
                                  'Aperçu indisponible pour ce fichier.',
                                ),
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
                      action: _createAttendanceEntry,
                      successMessage: 'Absence/retard enregistré.',
                    ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFeeForm() {
    return _openFloatingPanel(
      title: 'Nouveau frais scolaire',
      contentBuilder: (panelContext, refreshPanel) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                initialValue: _feeAcademicYearId,
                decoration: const InputDecoration(labelText: 'Année scolaire'),
                items: _years
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']} (ID ${row['id']})'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _feeAcademicYearId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _feeType,
                decoration: const InputDecoration(labelText: 'Type de frais'),
                items: const [
                  DropdownMenuItem(
                    value: 'registration',
                    child: Text('Inscription'),
                  ),
                  DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                  DropdownMenuItem(value: 'exam', child: Text('Examen')),
                ],
                onChanged: (value) {
                  _feeType = value ?? 'registration';
                  refreshPanel();
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate: _feeDueDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  _feeDueDate = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.event_note_outlined),
              label: Text('Échéance ${_apiDate(_feeDueDate)}'),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _feeAmountDueController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Montant dû'),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _createStudentFeeEntry,
                      successMessage: 'Frais scolaire ajouté.',
                    ),
              icon: const Icon(Icons.add_card_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPaymentForm() {
    if (_fees.isNotEmpty) {
      final feeIds = _fees.map((row) => _asInt(row['id'])).toSet();
      if (_paymentFeeId == null || !feeIds.contains(_paymentFeeId)) {
        _paymentFeeId = feeIds.first;
      }
    }

    return _openFloatingPanel(
      title: 'Nouveau paiement',
      contentBuilder: (panelContext, refreshPanel) {
        if (_fees.isEmpty) {
          return const Text('Ajoute un frais avant d’enregistrer un paiement.');
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 500,
              child: DropdownButtonFormField<int?>(
                initialValue: _paymentFeeId,
                decoration: const InputDecoration(labelText: 'Frais concerné'),
                items: _fees
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text(
                          '#${row['id']} • ${_feeTypeLabel((row['fee_type'] ?? '').toString())} • Solde ${_money(_toDouble(row['balance']))}',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _paymentFeeId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _paymentAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Montant'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _paymentMethodController,
                decoration: const InputDecoration(labelText: 'Méthode'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _paymentReferenceController,
                decoration: const InputDecoration(
                  labelText: 'Référence (optionnel)',
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: _createPaymentEntry,
                      successMessage: 'Paiement enregistré.',
                    ),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openStudentsByClassPanel() {
    final classPanelSearchController = TextEditingController();
    String panelQuery = '';

    final studentsByClass = <String, List<Student>>{};
    for (final student in _students) {
      final className = student.classroomName.trim().isEmpty
          ? 'Sans classe'
          : student.classroomName.trim();
      studentsByClass.putIfAbsent(className, () => []).add(student);
    }

    for (final group in studentsByClass.values) {
      group.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
    }

    final orderedClassNames = <String>[];
    final knownClassNames = <String>{};
    for (final row in _classrooms) {
      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty || !studentsByClass.containsKey(name)) continue;
      knownClassNames.add(name);
      orderedClassNames.add(name);
    }

    final otherClassNames =
        studentsByClass.keys
            .where(
              (name) =>
                  name != 'Sans classe' && !knownClassNames.contains(name),
            )
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final classNames = <String>[
      ...orderedClassNames,
      ...otherClassNames,
      if (studentsByClass.containsKey('Sans classe')) 'Sans classe',
    ];

    return _openFloatingPanel(
      title: 'Liste des élèves par classe',
      contentBuilder: (panelContext, refreshPanel) {
        if (_students.isEmpty) {
          return const Text('Aucun élève disponible.');
        }

        final normalizedQuery = panelQuery.trim().toLowerCase();
        final filteredStudentsByClass = <String, List<Student>>{};
        for (final className in classNames) {
          final group = studentsByClass[className] ?? const <Student>[];
          final filteredGroup = normalizedQuery.isEmpty
              ? group
              : group
                    .where(
                      (student) => _matchesClassPanelQuery(
                        student: student,
                        className: className,
                        query: normalizedQuery,
                      ),
                    )
                    .toList();
          if (filteredGroup.isNotEmpty) {
            filteredStudentsByClass[className] = filteredGroup;
          }
        }

        final displayedStudentsCount = filteredStudentsByClass.values.fold<int>(
          0,
          (sum, group) => sum + group.length,
        );

        return SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$displayedStudentsCount élèves affichés • ${filteredStudentsByClass.length} classes',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Clique sur un élève pour ouvrir son dossier.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: classPanelSearchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Recherche (nom ou matricule)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: panelQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            classPanelSearchController.clear();
                            panelQuery = '';
                            refreshPanel();
                          },
                        ),
                ),
                onChanged: (value) {
                  panelQuery = value;
                  refreshPanel();
                },
              ),
              const SizedBox(height: 8),
              if (filteredStudentsByClass.isEmpty)
                Text(
                  panelQuery.trim().isEmpty
                      ? 'Aucun élève disponible.'
                      : 'Aucun résultat pour "${panelQuery.trim()}".',
                )
              else
                ...filteredStudentsByClass.entries.map((entry) {
                  final className = entry.key;
                  final group = entry.value;
                  final totalInClass =
                      (studentsByClass[className] ?? const <Student>[]).length;
                  return Card(
                    child: ExpansionTile(
                      title: Text(
                        normalizedQuery.isEmpty
                            ? '$className (${group.length})'
                            : '$className (${group.length}/$totalInClass)',
                      ),
                      children: group
                          .map(
                            (student) => ListTile(
                              dense: true,
                              onTap: () {
                                if (panelContext.mounted) {
                                  final navigator = Navigator.of(panelContext);
                                  if (navigator.canPop()) {
                                    navigator.pop();
                                  }
                                }

                                if (!mounted) return;
                                setState(() {
                                  _selectedStudent = student;
                                  _selectedClassroomUpdateId =
                                      student.classroomId;
                                  _selectedParentUpdateId = student.parentId;
                                });
                                _loadStudentLinkedData(student.id);
                              },
                              leading: Icon(
                                student.isArchived
                                    ? Icons.archive_outlined
                                    : Icons.school_outlined,
                              ),
                              title: Text(student.fullName),
                              subtitle: Text(
                                'Matricule: ${student.matricule} • ${student.isArchived ? 'Archivé' : 'Actif'}',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    ).whenComplete(classPanelSearchController.dispose);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = _students.length;
    final active = _students.where((s) => !s.isArchived).length;
    final archived = total - active;
    final newEnrolled = _newlyEnrolledCount();
    final activeYearLabel = _activeAcademicYearLabel();
    final colorScheme = Theme.of(context).colorScheme;
    final totalFiltered = _filteredStudents.length;
    final totalPages = totalFiltered == 0
        ? 1
        : ((totalFiltered + _tableRowsPerPage - 1) ~/ _tableRowsPerPage);
    final currentPage = math.min(_tablePage, totalPages);
    final startIndex = totalFiltered == 0
        ? 0
        : (currentPage - 1) * _tableRowsPerPage;
    final endIndex = math.min(startIndex + _tableRowsPerPage, totalFiltered);
    final visibleStudents = totalFiltered == 0
        ? <Student>[]
        : _filteredStudents.sublist(startIndex, endIndex);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion des élèves',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Année scolaire : $activeYearLabel',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Inscription, attribution classe, matricule automatique, archivage, historique académique et dossier disciplinaire.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : _openRegistrationForm,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Ajouter un élève'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _saving ? null : _openStudentsByClassPanel,
                      icon: const Icon(Icons.view_list_outlined),
                      label: const Text('Liste par classe'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _saving ? null : _openClassCardsPanel,
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('Cartes classe'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _loadBaseData(
                              keepSelectedId: _selectedStudent?.id,
                            ),
                      icon: const Icon(Icons.sync),
                      label: const Text('Actualiser'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Recherche et filtres',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '$totalFiltered résultat${totalFiltered > 1 ? 's' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Rechercher un élève...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Effacer',
                                  icon: const Icon(Icons.clear),
                                  onPressed: _clearSearch,
                                ),
                        ),
                        onChanged: _onSearchChanged,
                        onSubmitted: (_) =>
                            _applyFilters(resetVisibleCount: true),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<int?>(
                        initialValue: _classFilterId,
                        decoration: const InputDecoration(labelText: 'Classe'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Toutes les classes'),
                          ),
                          ..._classrooms.map(
                            (row) => DropdownMenuItem<int?>(
                              value: _asInt(row['id']),
                              child: Text('${row['name']} (ID ${row['id']})'),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _classFilterId = value);
                          _applyFilters(resetVisibleCount: true);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        decoration: const InputDecoration(labelText: 'Statut'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Tous')),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Actifs'),
                          ),
                          DropdownMenuItem(
                            value: 'archived',
                            child: Text('Archivés'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _statusFilter = value ?? 'active');
                          _applyFilters(resetVisibleCount: true);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String>(
                        initialValue: _sortBy,
                        decoration: const InputDecoration(
                          labelText: 'Trier par',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'name', child: Text('Nom')),
                          DropdownMenuItem(
                            value: 'matricule',
                            child: Text('Matricule'),
                          ),
                          DropdownMenuItem(
                            value: 'classroom',
                            child: Text('Classe'),
                          ),
                          DropdownMenuItem(
                            value: 'status',
                            child: Text('Statut'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _sortBy = value ?? 'name');
                          _applyFilters(resetVisibleCount: true);
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _sortAscending = !_sortAscending);
                        _applyFilters(resetVisibleCount: true);
                      },
                      icon: Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                      ),
                      label: Text(_sortAscending ? 'Ascendant' : 'Descendant'),
                    ),
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _applyFilters(resetVisibleCount: true),
                      icon: const Icon(Icons.filter_alt_outlined),
                      label: const Text('Filtrer'),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _resetStudentsFilters,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Réinitialiser'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Liste des élèves (${_filteredStudents.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_selectedStudent != null)
                      Chip(
                        avatar: const Icon(Icons.person_outline, size: 16),
                        label: SizedBox(
                          width: 220,
                          child: Text(
                            _selectedStudent!.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_filteredStudents.isEmpty)
                  const Text('Aucun élève trouvé avec ces critères.')
                else ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showBottomBorder: true,
                      border: TableBorder.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                        width: 0.7,
                      ),
                      headingRowColor: WidgetStatePropertyAll(
                        colorScheme.surfaceContainerHighest,
                      ),
                      columnSpacing: 22,
                      horizontalMargin: 12,
                      headingRowHeight: 46,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 62,
                      columns: const [
                        DataColumn(label: Text('N°')),
                        DataColumn(label: Text('Matricule')),
                        DataColumn(label: Text('Nom complet')),
                        DataColumn(label: Text('Classe')),
                        DataColumn(label: Text('Date naissance')),
                        DataColumn(label: Text('Téléphone')),
                        DataColumn(label: Text('Statut')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: visibleStudents.asMap().entries.map((entry) {
                        final rowIndex = entry.key;
                        final student = entry.value;
                        final selected = _selectedStudent?.id == student.id;
                        return DataRow(
                          selected: selected,
                          onSelectChanged: (_) => _activateStudent(student),
                          cells: [
                            DataCell(Text('${startIndex + rowIndex + 1}')),
                            DataCell(Text(student.matricule)),
                            DataCell(
                              Text(
                                student.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DataCell(
                              Text(
                                student.classroomName.isEmpty
                                    ? 'Non attribuée'
                                    : student.classroomName,
                              ),
                            ),
                            DataCell(
                              Text(
                                student.birthDate == null
                                    ? '-'
                                    : _apiDate(student.birthDate!),
                              ),
                            ),
                            DataCell(
                              Text(
                                student.phone.trim().isEmpty
                                    ? '-'
                                    : student.phone,
                              ),
                            ),
                            DataCell(
                              _statusBadge(
                                student.isArchived ? 'Archivé' : 'Actif',
                                student.isArchived,
                              ),
                            ),
                            DataCell(
                              Wrap(
                                spacing: 4,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () => _activateStudent(student),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Voir'),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () {
                                            _activateStudent(student);
                                            _openProfileForm();
                                          },
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Éditer'),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: colorScheme.error,
                                    ),
                                    onPressed: _saving
                                        ? null
                                        : () => _toggleArchive(student),
                                    icon: Icon(
                                      student.isArchived
                                          ? Icons.restore_from_trash_outlined
                                          : Icons.delete_outline,
                                      size: 16,
                                    ),
                                    label: Text(
                                      student.isArchived
                                          ? 'Restaurer'
                                          : 'Supprimer',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        totalFiltered == 0
                            ? 'Aucun résultat'
                            : 'Affichage ${startIndex + 1}-$endIndex sur $totalFiltered',
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Lignes/page:'),
                          const SizedBox(width: 6),
                          DropdownButton<int>(
                            value: _tableRowsPerPage,
                            items: _tableRowsPerPageOptions
                                .map(
                                  (rows) => DropdownMenuItem<int>(
                                    value: rows,
                                    child: Text('$rows'),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null || value == _tableRowsPerPage) {
                                return;
                              }
                              setState(() {
                                _tableRowsPerPage = value;
                                _tablePage = 1;
                              });
                              _applyFilters(resetVisibleCount: true);
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Première page',
                            onPressed: currentPage > 1
                                ? () => setState(() => _tablePage = 1)
                                : null,
                            icon: const Icon(Icons.first_page),
                          ),
                          IconButton(
                            tooltip: 'Page précédente',
                            onPressed: currentPage > 1
                                ? () => setState(
                                    () => _tablePage = currentPage - 1,
                                  )
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text('Page $currentPage / $totalPages'),
                          IconButton(
                            tooltip: 'Page suivante',
                            onPressed: currentPage < totalPages
                                ? () => setState(
                                    () => _tablePage = currentPage + 1,
                                  )
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                          IconButton(
                            tooltip: 'Dernière page',
                            onPressed: currentPage < totalPages
                                ? () => setState(() => _tablePage = totalPages)
                                : null,
                            icon: const Icon(Icons.last_page),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _overviewMetricCard(
              title: 'Nombre total d’élèves',
              value: '$total',
              icon: Icons.groups_2_outlined,
            ),
            _overviewMetricCard(
              title: 'Actifs',
              value: '$active',
              icon: Icons.verified_user_outlined,
            ),
            _overviewMetricCard(
              title: 'Archivés',
              value: '$archived',
              icon: Icons.archive_outlined,
            ),
            _overviewMetricCard(
              title: 'Nouveaux inscrits',
              value: '$newEnrolled',
              icon: Icons.person_add_alt_1_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: _selectedStudent == null
                ? const Text(
                    'Sélectionne un élève pour voir son dossier complet.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Dossier élève: ${_selectedStudent!.fullName}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Matricule: ${_selectedStudent!.matricule}'),
                      Text(
                        'Classe actuelle: ${_selectedStudent!.classroomName.isEmpty ? 'Non attribuée' : _selectedStudent!.classroomName}',
                      ),
                      Text(
                        'Parent: ${_selectedStudent!.parentName.isEmpty ? 'Non attribué' : _selectedStudent!.parentName}',
                      ),
                      if (_selectedStudent!.phone.trim().isNotEmpty)
                        Text('Téléphone: ${_selectedStudent!.phone}'),
                      if (_selectedStudent!.email.trim().isNotEmpty)
                        Text('Email: ${_selectedStudent!.email}'),
                      Text(
                        'Date de naissance: ${_selectedStudent!.birthDate == null ? 'Non renseignée' : _apiDate(_selectedStudent!.birthDate!)}',
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _saving ? null : _openProfileForm,
                            icon: const Icon(Icons.edit_note_outlined),
                            label: const Text('Modifier dossier'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _saving
                                ? null
                                : () => _toggleArchive(_selectedStudent!),
                            icon: Icon(
                              _selectedStudent!.isArchived
                                  ? Icons.unarchive_outlined
                                  : Icons.archive_outlined,
                            ),
                            label: Text(
                              _selectedStudent!.isArchived
                                  ? 'Réactiver'
                                  : 'Archiver',
                            ),
                          ),
                          if (_selectedStudent!.photo.trim().isNotEmpty)
                            FilledButton.tonalIcon(
                              onPressed: _saving
                                  ? null
                                  : () => _viewProfilePhoto(
                                      _selectedStudent!.photo,
                                    ),
                              icon: const Icon(Icons.account_box_outlined),
                              label: const Text('Voir photo'),
                            ),
                          FilledButton.tonalIcon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final success = await _printStudentCard();
                                    if (success) {
                                      _showMessage(
                                        'Carte élève prête à l’impression.',
                                        isSuccess: true,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.badge_outlined),
                            label: const Text('Carte élève'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final success =
                                        await _quickPreviewStudentCard();
                                    if (success) {
                                      _showMessage(
                                        'Aperçu rapide affiché.',
                                        isSuccess: true,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Aperçu rapide'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final success =
                                        await _exportStudentCardPdf();
                                    if (success) {
                                      _showMessage(
                                        'Carte élève exportée en PDF.',
                                        isSuccess: true,
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.picture_as_pdf_outlined),
                            label: const Text('Exporter PDF'),
                          ),
                        ],
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
                            _metricChip(
                              'Historique académique',
                              '${_history.length}',
                            ),
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
                        Text(
                          'Actions rapides',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _openHistoryForm,
                              icon: const Icon(Icons.history_edu_outlined),
                              label: const Text('Historique'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _openIncidentForm,
                              icon: const Icon(Icons.gavel_outlined),
                              label: const Text('Discipline'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _openAttendanceForm,
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Absence/Retard'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _openFeeForm,
                              icon: const Icon(Icons.add_card_outlined),
                              label: const Text('Nouveau frais'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _openPaymentForm,
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Nouveau paiement'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ExpansionTile(
                          title: Text(
                            'Historique académique (${_history.length})',
                          ),
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
                        ExpansionTile(
                          title: Text(
                            'Dossier disciplinaire (${_incidents.length})',
                          ),
                          children: _incidents.isEmpty
                              ? const [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                                    child: Text(
                                      'Aucun incident disciplinaire.',
                                    ),
                                  ),
                                ]
                              : _incidents.take(20).map((row) {
                                  final isResolved =
                                      (row['status'] ?? '').toString() ==
                                      'resolved';
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      '${row['category'] ?? 'Incident'} • ${row['incident_date'] ?? ''}',
                                    ),
                                    subtitle: Text(
                                      '${row['description'] ?? ''}\nStatut: ${isResolved ? 'Traité' : 'Ouvert'} • Gravité: ${_severityLabel((row['severity'] ?? '').toString())}',
                                    ),
                                    isThreeLine: true,
                                    trailing: IconButton(
                                      tooltip: isResolved
                                          ? 'Rouvrir incident'
                                          : 'Marquer traité',
                                      icon: Icon(
                                        isResolved
                                            ? Icons.undo_outlined
                                            : Icons.check_circle_outline,
                                      ),
                                      onPressed: _saving
                                          ? null
                                          : () => _toggleIncidentStatus(row),
                                    ),
                                  );
                                }).toList(),
                        ),
                        ExpansionTile(
                          title: Text(
                            'Absences & retards (${_attendances.length})',
                          ),
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
                                  final proofThumbSize =
                                      MediaQuery.of(context).size.width < 720
                                      ? 36.0
                                      : 44.0;
                                  final proofIconSize = proofThumbSize < 40
                                      ? 16.0
                                      : 18.0;
                                  final proofUrl = hasProof
                                      ? _resolveMediaUrl(proofPath)
                                      : '';
                                  return ListTile(
                                    dense: true,
                                    leading: hasProof
                                        ? GestureDetector(
                                            onTap: () =>
                                                _viewAttendanceProof(proofPath),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Container(
                                                width: proofThumbSize,
                                                height: proofThumbSize,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                                child: Image.network(
                                                  proofUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return Icon(
                                                          Icons
                                                              .image_not_supported_outlined,
                                                          size: proofIconSize,
                                                        );
                                                      },
                                                ),
                                              ),
                                            ),
                                          )
                                        : null,
                                    title: Text('${row['date'] ?? ''}'),
                                    subtitle: Text(
                                      'Absent: ${row['is_absent'] == true ? 'Oui' : 'Non'} • Retard: ${row['is_late'] == true ? 'Oui' : 'Non'} • Justificatif: ${hasProof ? 'Oui' : 'Non'}'
                                      '${hasProof ? '\nFichier: ${_fileNameFromPath(proofPath)}' : ''}',
                                    ),
                                    isThreeLine: hasProof,
                                  );
                                }).toList(),
                        ),
                        ExpansionTile(
                          title: Text(
                            'Frais & paiements (${_fees.length} frais / ${_payments.length} paiements)',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Actions financières',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: _saving
                                            ? null
                                            : _openFeeForm,
                                        icon: const Icon(
                                          Icons.add_card_outlined,
                                        ),
                                        label: const Text('Nouveau frais'),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: _saving
                                            ? null
                                            : _openPaymentForm,
                                        icon: const Icon(
                                          Icons.payments_outlined,
                                        ),
                                        label: const Text('Nouveau paiement'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Total dû: ${_money(_fees.fold<double>(0, (sum, row) => sum + _toDouble(row['amount_due'])))} • '
                                    'Total payé: ${_money(_fees.fold<double>(0, (sum, row) => sum + _toDouble(row['amount_paid'])))} • '
                                    'Solde: ${_money(_fees.fold<double>(0, (sum, row) => sum + _toDouble(row['balance'])))}',
                                  ),
                                ],
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
                                      trailing: IconButton(
                                        tooltip: 'Imprimer reçu',
                                        icon: const Icon(
                                          Icons.receipt_long_outlined,
                                        ),
                                        onPressed: () {
                                          final paymentId = _asInt(row['id']);
                                          if (paymentId <= 0) {
                                            _showMessage(
                                              'Paiement invalide pour impression.',
                                            );
                                            return;
                                          }
                                          _printPaymentReceipt(paymentId);
                                        },
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  void _activateStudent(Student student) {
    setState(() {
      _selectedStudent = student;
      _selectedClassroomUpdateId = student.classroomId;
      _selectedParentUpdateId = student.parentId;
    });
    _loadStudentLinkedData(student.id);
  }

  int _newlyEnrolledCount() {
    DateTime? start;
    DateTime? end;

    for (final row in _years) {
      if (row['is_active'] == true) {
        start = _parseDate(row['start_date']);
        end = _parseDate(row['end_date']);
        break;
      }
    }

    if (start == null || end == null) {
      final now = DateTime.now();
      start = DateTime(now.year, 1, 1);
      end = DateTime(now.year, 12, 31, 23, 59, 59);
    }

    return _students.where((student) {
      final enrolledAt = student.enrollmentDate;
      if (enrolledAt == null) return false;
      return !enrolledAt.isBefore(start!) && !enrolledAt.isAfter(end!);
    }).length;
  }

  String _activeAcademicYearLabel() {
    Map<String, dynamic>? activeYear;
    for (final row in _years) {
      if (row['is_active'] == true) {
        activeYear = row;
        break;
      }
    }

    if (activeYear == null && _feeAcademicYearId != null) {
      for (final row in _years) {
        if (_asInt(row['id']) == _feeAcademicYearId) {
          activeYear = row;
          break;
        }
      }
    }

    activeYear ??= _years.isNotEmpty ? _years.first : null;
    if (activeYear == null) return 'Non définie';
    return _academicYearLabel(activeYear);
  }

  String _academicYearLabel(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;

    final start = row['start_date']?.toString().trim() ?? '';
    final end = row['end_date']?.toString().trim() ?? '';
    if (start.isNotEmpty || end.isNotEmpty) {
      return '$start - $end';
    }

    return 'Année ${row['id'] ?? ''}'.trim();
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Widget _overviewMetricCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 16, child: Icon(icon, size: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(value, style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String label, bool archived) {
    final scheme = Theme.of(context).colorScheme;
    final background = archived
        ? scheme.surfaceContainerHighest
        : scheme.primary.withValues(alpha: 0.14);
    final foreground = archived ? scheme.onSurfaceVariant : scheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text('$label: $value'),
    );
  }

  String _parentLabel(Map<String, dynamic> row) {
    final first = (row['user_first_name'] ?? row['first_name'] ?? '')
        .toString();
    final last = (row['user_last_name'] ?? row['last_name'] ?? '').toString();
    final name = '$first $last'.trim();
    final user = (row['user'] ?? '').toString();
    if (name.isNotEmpty) return '$name (ID ${row['id']})';
    if (user.isNotEmpty) return '$user (ID ${row['id']})';
    return 'Parent ID ${row['id']}';
  }

  bool _matchesClassPanelQuery({
    required Student student,
    required String className,
    required String query,
  }) {
    if (query.isEmpty) return true;
    final haystack = '${student.fullName} ${student.matricule} $className'
        .toLowerCase();
    return haystack.contains(query);
  }

  int _compareStudents(Student a, Student b) {
    int result;
    switch (_sortBy) {
      case 'matricule':
        result = a.matricule.toLowerCase().compareTo(b.matricule.toLowerCase());
        break;
      case 'classroom':
        result = a.classroomName.toLowerCase().compareTo(
          b.classroomName.toLowerCase(),
        );
        if (result == 0) {
          result = a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        }
        break;
      case 'status':
        result = (a.isArchived ? 1 : 0).compareTo(b.isArchived ? 1 : 0);
        if (result == 0) {
          result = a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        }
        break;
      case 'name':
      default:
        result = a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        break;
    }
    return _sortAscending ? result : -result;
  }

  String _classroomName(int classroomId) {
    for (final row in _classrooms) {
      if (_asInt(row['id']) == classroomId) {
        return row['name']?.toString() ?? 'Classe $classroomId';
      }
    }
    return 'Classe $classroomId';
  }

  String _yearName(int yearId) {
    for (final row in _years) {
      if (_asInt(row['id']) == yearId) {
        return row['name']?.toString() ?? 'Année $yearId';
      }
    }
    return 'Année $yearId';
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  String _money(double value) => '${value.toStringAsFixed(0)} FCFA';

  String _feeTypeLabel(String value) {
    switch (value) {
      case 'registration':
        return 'Inscription';
      case 'monthly':
        return 'Mensuel';
      case 'exam':
        return 'Examen';
      default:
        return value.isEmpty ? 'Non défini' : value;
    }
  }

  String _severityLabel(String value) {
    switch (value) {
      case 'low':
        return 'Faible';
      case 'high':
        return 'Élevée';
      default:
        return 'Moyenne';
    }
  }

  String _apiDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _fileNameFromPath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '';
    final index = normalized.lastIndexOf('/');
    if (index >= 0 && index < normalized.length - 1) {
      return normalized.substring(index + 1);
    }
    return normalized;
  }

  String _resolveMediaUrl(String value) {
    final normalized = value.trim();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }

    final baseUrl = ref
        .read(studentsRepositoryProvider)
        .dio
        .options
        .baseUrl
        .trim();
    if (baseUrl.isEmpty) return normalized;

    try {
      return Uri.parse(baseUrl).resolve(normalized).toString();
    } catch (_) {
      return normalized;
    }
  }

  Future<void> _previewMemoryImage(
    Uint8List bytes, {
    required String title,
  }) async {
    if (bytes.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 700),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: InteractiveViewer(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Text('Impossible d’afficher cette image.'),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Fermer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showNetworkImageDialog({
    required String title,
    required String mediaPath,
    required String emptyMessage,
  }) async {
    final normalized = mediaPath.trim();
    if (normalized.isEmpty) {
      _showMessage(emptyMessage);
      return;
    }

    final imageUrl = _resolveMediaUrl(normalized);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 700),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: InteractiveViewer(
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              'Impossible d’afficher l’image.\nURL: $imageUrl',
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Fermer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _viewProfilePhoto(String photoPath) {
    return _showNetworkImageDialog(
      title: 'Photo de profil',
      mediaPath: photoPath,
      emptyMessage: 'Aucune photo de profil disponible.',
    );
  }

  Future<void> _viewAttendanceProof(String proofPath) async {
    return _showNetworkImageDialog(
      title: 'Justificatif',
      mediaPath: proofPath,
      emptyMessage: 'Aucun justificatif disponible.',
    );
  }

  String _apiDateOrEmpty(DateTime? value) {
    if (value == null) return '';
    return _apiDate(value);
  }

  Future<void> _showRegistrationFailure(String message) async {
    _showMessage(message);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Inscription élève'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  String _extractErrorMessage(Object error) {
    if (error is DioException) {
      final responseData = error.response?.data;
      final parsed = _extractErrorText(responseData);
      if (parsed.isNotEmpty) return parsed;

      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        return 'Session expirée. Reconnecte-toi puis réessaie.';
      }
      if (statusCode == 403) {
        return 'Accès refusé pour créer un élève avec ce compte.';
      }
      if (statusCode != null) {
        return 'Erreur serveur ($statusCode) pendant l’inscription.';
      }

      if (error.type == DioExceptionType.connectionError) {
        return 'Impossible de contacter le serveur API.';
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Le serveur met trop de temps à répondre.';
      }

      final fallback = error.message?.trim() ?? '';
      return fallback.isEmpty
          ? 'Erreur réseau pendant l’inscription.'
          : fallback;
    }

    final raw = error.toString().trim();
    if (raw.startsWith('Exception:')) {
      final normalized = raw.substring('Exception:'.length).trim();
      return normalized.isEmpty ? 'Erreur pendant l’inscription.' : normalized;
    }
    return raw.isEmpty ? 'Erreur pendant l’inscription.' : raw;
  }

  String _extractErrorText(dynamic data) {
    if (data == null) return '';

    if (data is String) {
      return data.trim();
    }

    if (data is List) {
      for (final item in data) {
        final value = _extractErrorText(item);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    if (data is Map) {
      const priorityKeys = [
        'detail',
        'non_field_errors',
        'username',
        'password',
        'user',
        'classroom',
        'parent',
      ];

      for (final key in priorityKeys) {
        if (!data.containsKey(key)) continue;
        final value = _extractErrorText(data[key]);
        if (value.isNotEmpty) return value;
      }

      for (final value in data.values) {
        final parsed = _extractErrorText(value);
        if (parsed.isNotEmpty) return parsed;
      }
    }

    return data.toString().trim();
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isSuccess ? Colors.green.shade700 : null,
      ),
    );
  }
}
