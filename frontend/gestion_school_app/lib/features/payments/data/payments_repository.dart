import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/models/paginated_result.dart';
import '../domain/payment.dart';
import '../domain/student_fee.dart';

class PaymentsRepository {
  final Dio dio;

  PaymentsRepository(this.dio);

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return [];
  }

  Future<PaginatedResult<PaymentItem>> fetchPaymentsPage({
    int page = 1,
    int pageSize = 25,
    String search = '',
    String? method,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (method != null && method.trim().isNotEmpty) 'method': method,
      'ordering': '-created_at',
    };

    final response = await dio.get('/payments/', queryParameters: query);
    final rows = _extractRows(response.data);

    final mapped = rows.map((row) {
      final map = row as Map<String, dynamic>;
      return PaymentItem(
        id: map['id'] as int,
        feeId: map['fee'] as int,
        amount: _toDouble(map['amount']),
        method: map['method']?.toString() ?? '',
        reference: map['reference']?.toString() ?? '',
        studentFullName: map['student_full_name']?.toString() ?? '',
        studentMatricule: map['student_matricule']?.toString() ?? '',
        classroomName: map['classroom_name']?.toString() ?? '',
        feeType: map['fee_type']?.toString() ?? '',
        createdAt: map['created_at']?.toString() ?? '',
      );
    }).toList();

    final payload = response.data;
    if (payload is Map<String, dynamic>) {
      return PaginatedResult<PaymentItem>(
        count: payload['count'] as int? ?? mapped.length,
        next: payload['next']?.toString(),
        previous: payload['previous']?.toString(),
        results: mapped,
      );
    }

    return PaginatedResult<PaymentItem>(
      count: mapped.length,
      next: null,
      previous: null,
      results: mapped,
    );
  }

  Future<List<PaymentItem>> fetchPayments() async {
    final page = await fetchPaymentsPage(page: 1, pageSize: 120);
    return page.results;
  }

  Future<List<PaymentItem>> fetchPaymentsForJournal({
    String search = '',
    String? method,
  }) async {
    final rows = <PaymentItem>[];
    var page = 1;
    while (true) {
      final batch = await fetchPaymentsPage(
        page: page,
        pageSize: 200,
        search: search,
        method: method,
      );
      rows.addAll(batch.results);
      if (!batch.hasNext || page >= 200) {
        break;
      }
      page += 1;
    }
    return rows;
  }

  Future<Uint8List> exportPaymentsJournal({
    required String format,
    String search = '',
    String? method,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await dio.get<List<int>>(
      '/reports/journal-payments/export/',
      queryParameters: {
        'export_format': format,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (method != null && method.trim().isNotEmpty) 'method': method,
        if (dateFrom != null && dateFrom.trim().isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.trim().isNotEmpty) 'date_to': dateTo,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Export vide');
    }
    return Uint8List.fromList(bytes);
  }

  Future<List<StudentFeeItem>> fetchFees() async {
    final response = await dio.get(
      '/fees/',
      queryParameters: {'page_size': 120},
    );
    final rows = _extractRows(response.data);

    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return StudentFeeItem(
        id: map['id'] as int,
        studentFullName: map['student_full_name']?.toString() ?? '',
        studentMatricule: map['student_matricule']?.toString() ?? '',
        classroomName: map['classroom_name']?.toString() ?? '',
        feeType: map['fee_type']?.toString() ?? '',
        amountDue: _toDouble(map['amount_due']),
        balance: _toDouble(map['balance']),
      );
    }).toList();
  }

  Future<void> createPayment({
    required int feeId,
    required double amount,
    required String method,
    required String reference,
  }) async {
    await dio.post(
      '/payments/',
      data: {
        'fee': feeId,
        'amount': amount,
        'method': method,
        'reference': reference,
      },
    );
  }

  Future<void> updatePayment({
    required int paymentId,
    required int feeId,
    required double amount,
    required String method,
    required String reference,
  }) async {
    await dio.patch(
      '/payments/$paymentId/',
      data: {
        'fee': feeId,
        'amount': amount,
        'method': method,
        'reference': reference,
      },
    );
  }

  Future<void> deletePayment(int paymentId) async {
    await dio.delete('/payments/$paymentId/');
  }

  Future<Uint8List> fetchReceiptPdf(int paymentId) async {
    final response = await dio.get<List<int>>(
      '/reports/receipt/$paymentId/',
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('PDF vide');
    }
    return Uint8List.fromList(bytes);
  }

  String receiptUrl(int paymentId) =>
      '${ApiConstants.baseUrl}/reports/receipt/$paymentId/';

  String _normalizeMonthDate(String month) {
    final cleaned = month.trim();
    if (RegExp(r'^\d{4}-\d{2}$').hasMatch(cleaned)) {
      return '$cleaned-01';
    }
    return cleaned;
  }

  Future<List<Map<String, dynamic>>> fetchTeachers() async {
    final response = await dio.get(
      '/teachers/',
      queryParameters: {
        'page_size': 500,
        'ordering': 'user__last_name,user__first_name',
      },
    );
    final rows = _extractRows(response.data);
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchTeacherTimeEntries() async {
    final response = await dio.get('/teacher-time-entries/');
    final rows = _extractRows(response.data);
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> createTeacherTimeEntry({
    required int teacherId,
    required String entryDate,
    required String checkInTime,
    String? checkOutTime,
    String notes = '',
  }) async {
    await dio.post(
      '/teacher-time-entries/',
      data: {
        'teacher': teacherId,
        'entry_date': entryDate,
        'check_in_time': checkInTime,
        if (checkOutTime?.trim().isNotEmpty ?? false)
          'check_out_time': checkOutTime,
        'notes': notes,
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchTeacherPayrolls({String? month}) async {
    final query = <String, dynamic>{};
    if (month != null && month.trim().isNotEmpty) {
      query['month'] = _normalizeMonthDate(month);
    }
    final response = await dio.get('/teacher-payrolls/', queryParameters: query);
    final rows = _extractRows(response.data);
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> generateTeacherPayroll({
    required String month,
    int? teacherId,
  }) async {
    final payload = <String, dynamic>{'month': month};
    if (teacherId != null) {
      payload['teacher'] = teacherId;
    }

    final response = await dio.post(
      '/teacher-payrolls/generate_monthly/',
      data: payload,
    );

    final data = response.data;
    if (data is Map<String, dynamic> && data['results'] is List<dynamic>) {
      return (data['results'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }

    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> validateTeacherPayrollLevelOne(int payrollId) async {
    final response = await dio.post('/teacher-payrolls/$payrollId/validate_level_one/');
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> validateTeacherPayrollLevelTwo(int payrollId) async {
    final response = await dio.post('/teacher-payrolls/$payrollId/validate_level_two/');
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> resetTeacherPayrollValidation(int payrollId) async {
    final response = await dio.post('/teacher-payrolls/$payrollId/reset_validation/');
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> fetchExpenses() async {
    final response = await dio.get(
      '/expenses/',
      queryParameters: {
        'page_size': 500,
        'ordering': '-date,-id',
      },
    );
    final rows = _extractRows(response.data);
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchExpensesForJournal({
    String search = '',
    String? category,
    String? stage,
    String? dateFrom,
    String? dateTo,
  }) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final response = await dio.get(
        '/reports/journal/expenses/',
        queryParameters: {
          'page': page,
          'page_size': 200,
          if (search.trim().isNotEmpty) 'search': search.trim(),
          if (category != null && category.trim().isNotEmpty) 'category': category,
          if (stage != null && stage.trim().isNotEmpty) 'stage': stage,
          if (dateFrom != null && dateFrom.trim().isNotEmpty) 'date_from': dateFrom,
          if (dateTo != null && dateTo.trim().isNotEmpty) 'date_to': dateTo,
        },
      );
      final payload = response.data;
      rows.addAll(_extractRows(payload).whereType<Map<String, dynamic>>());
      final hasNext = payload is Map<String, dynamic> && payload['next'] != null;
      if (!hasNext || page >= 200) {
        break;
      }
      page += 1;
    }
    return rows;
  }

  Future<Uint8List> exportExpensesJournal({
    required String format,
    String search = '',
    String? category,
    String? stage,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await dio.get<List<int>>(
      '/reports/journal-expenses/export/',
      queryParameters: {
        'export_format': format,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (category != null && category.trim().isNotEmpty) 'category': category,
        if (stage != null && stage.trim().isNotEmpty) 'stage': stage,
        if (dateFrom != null && dateFrom.trim().isNotEmpty) 'date_from': dateFrom,
        if (dateTo != null && dateTo.trim().isNotEmpty) 'date_to': dateTo,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Export vide');
    }
    return Uint8List.fromList(bytes);
  }

  Future<Map<String, dynamic>> validateExpenseLevelOne(int expenseId) async {
    final response = await dio.post('/expenses/$expenseId/validate_level_one/');
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> validateExpenseLevelTwo(int expenseId) async {
    final response = await dio.post('/expenses/$expenseId/validate_level_two/');
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> resetExpenseValidation(int expenseId) async {
    final response = await dio.post('/expenses/$expenseId/reset_validation/');
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createExpense({
    required String label,
    required double amount,
    required String date,
    required String category,
    String notes = '',
  }) async {
    final response = await dio.post(
      '/expenses/',
      data: {
        'label': label,
        'amount': amount,
        'date': date,
        'category': category,
        'notes': notes,
      },
    );
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateExpense({
    required int expenseId,
    required String label,
    required double amount,
    required String date,
    required String category,
    String notes = '',
  }) async {
    final response = await dio.patch(
      '/expenses/$expenseId/',
      data: {
        'label': label,
        'amount': amount,
        'date': date,
        'category': category,
        'notes': notes,
      },
    );
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<void> deleteExpense(int expenseId) async {
    await dio.delete('/expenses/$expenseId/');
  }
}
