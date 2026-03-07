import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/api_constants.dart';
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

  Future<List<PaymentItem>> fetchPayments() async {
    final response = await dio.get('/payments/');
    final rows = _extractRows(response.data);

    return rows.map((row) {
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
  }

  Future<List<StudentFeeItem>> fetchFees() async {
    final response = await dio.get('/fees/');
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
