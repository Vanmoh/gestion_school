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
}
