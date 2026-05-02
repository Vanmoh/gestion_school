import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

class ImportTemplateDownload {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  const ImportTemplateDownload({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });
}

class AcademicImportsRepository {
  final Dio dio;

  AcademicImportsRepository(this.dio);

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return (data['results'] as List<dynamic>)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    if (data is List) {
      return data
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> fetchClassrooms() async {
    final response = await dio.get('/classrooms/');
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchAcademicYears() async {
    final response = await dio.get('/academic-years/');
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchExamSessions() async {
    final response = await dio.get('/exam-sessions/');
    return _extractRows(response.data);
  }

  Future<Map<String, dynamic>> previewStudentsImport({
    required int classroomId,
    required PlatformFile file,
  }) {
    return _submitImport(
      endpoint: '/students/import-by-class/',
      fields: <String, dynamic>{'classroom_id': classroomId, 'confirm': false},
      file: file,
    );
  }

  Future<Map<String, dynamic>> confirmStudentsImport({
    required int classroomId,
    required PlatformFile file,
  }) {
    return _submitImport(
      endpoint: '/students/import-by-class/',
      fields: <String, dynamic>{'classroom_id': classroomId, 'confirm': true},
      file: file,
    );
  }

  Future<Map<String, dynamic>> previewControlsImport({
    required int classroomId,
    required int academicYearId,
    required String term,
    required PlatformFile file,
  }) {
    return _submitImport(
      endpoint: '/grades/import-controls/',
      fields: <String, dynamic>{
        'classroom_id': classroomId,
        'academic_year_id': academicYearId,
        'term': term,
        'confirm': false,
      },
      file: file,
    );
  }

  Future<Map<String, dynamic>> confirmControlsImport({
    required int classroomId,
    required int academicYearId,
    required String term,
    required PlatformFile file,
  }) {
    return _submitImport(
      endpoint: '/grades/import-controls/',
      fields: <String, dynamic>{
        'classroom_id': classroomId,
        'academic_year_id': academicYearId,
        'term': term,
        'confirm': true,
      },
      file: file,
    );
  }

  Future<Map<String, dynamic>> previewExamsImport({
    required int classroomId,
    required int sessionId,
    required PlatformFile file,
  }) {
    return _submitImport(
      endpoint: '/exam-results/import-exams/',
      fields: <String, dynamic>{
        'classroom_id': classroomId,
        'session_id': sessionId,
        'confirm': false,
      },
      file: file,
    );
  }

  Future<Map<String, dynamic>> confirmExamsImport({
    required int classroomId,
    required int sessionId,
    required PlatformFile file,
  }) {
    return _submitImport(
      endpoint: '/exam-results/import-exams/',
      fields: <String, dynamic>{
        'classroom_id': classroomId,
        'session_id': sessionId,
        'confirm': true,
      },
      file: file,
    );
  }

  Future<Map<String, dynamic>> previewTimetableImport({
    required int classroomId,
    required PlatformFile file,
  }) {
    return _submitImport(
      endpoint: '/teacher-schedule-slots/import-by-class/',
      fields: <String, dynamic>{'classroom_id': classroomId, 'confirm': false},
      file: file,
    );
  }

  Future<Map<String, dynamic>> confirmTimetableImport({
    required int classroomId,
    required PlatformFile file,
    required bool confirmConflicts,
  }) {
    return _submitImport(
      endpoint: '/teacher-schedule-slots/import-by-class/',
      fields: <String, dynamic>{
        'classroom_id': classroomId,
        'confirm': true,
        'confirm_conflicts': confirmConflicts,
      },
      file: file,
    );
  }

  Future<ImportTemplateDownload> downloadImportTemplate({
    required String importType,
    required String format,
  }) async {
    final normalizedFormat = format.trim().toLowerCase();
    final response = await dio.get(
      '/import-templates/download/',
      queryParameters: <String, dynamic>{
        'type': importType,
        'format': normalizedFormat,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    final data = response.data;
    Uint8List bytes;
    if (data is Uint8List) {
      bytes = data;
    } else if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else if (data is List) {
      bytes = Uint8List.fromList(data.cast<int>());
    } else {
      throw Exception('Réponse binaire invalide pour le modèle.');
    }

    final headers = response.headers;
    final contentDisposition = headers.value('content-disposition') ?? '';
    final inferredName = _extractFilename(contentDisposition);
    final fallbackName = 'import_template_${importType}_$normalizedFormat.$normalizedFormat';
    final fileName = inferredName.isEmpty ? fallbackName : inferredName;

    return ImportTemplateDownload(
      bytes: bytes,
      fileName: fileName,
      mimeType: headers.value('content-type') ?? '',
    );
  }

  Future<Map<String, dynamic>> _submitImport({
    required String endpoint,
    required Map<String, dynamic> fields,
    required PlatformFile file,
  }) async {
    final multipartFile = await _buildMultipartFile(file);
    final payload = <String, dynamic>{...fields, 'file': multipartFile};
    final response = await dio.post(endpoint, data: FormData.fromMap(payload));
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<MultipartFile> _buildMultipartFile(PlatformFile file) async {
    final safeName = file.name.trim().isEmpty ? 'import.csv' : file.name.trim();
    final bytes = file.bytes;

    if (bytes != null && bytes.isNotEmpty) {
      return MultipartFile.fromBytes(bytes, filename: safeName);
    }

    final path = file.path;
    if (path != null && path.trim().isNotEmpty) {
      return MultipartFile.fromFile(path, filename: safeName);
    }

    throw Exception('Fichier illisible. Re-sélectionnez le document.');
  }

  String _extractFilename(String contentDisposition) {
    final candidates = contentDisposition.split(';');
    for (final chunk in candidates) {
      final value = chunk.trim();
      if (!value.toLowerCase().startsWith('filename=')) {
        continue;
      }
      final raw = value.substring('filename='.length).trim();
      return raw.replaceAll('"', '');
    }
    return '';
  }
}