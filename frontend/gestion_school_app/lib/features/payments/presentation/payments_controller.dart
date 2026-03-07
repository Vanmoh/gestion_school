import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/payments_repository.dart';
import '../domain/payment.dart';
import '../domain/student_fee.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return PaymentsRepository(ref.read(dioProvider));
});

final paymentsProvider = FutureProvider<List<PaymentItem>>((ref) async {
  return ref.read(paymentsRepositoryProvider).fetchPayments();
});

final feesProvider = FutureProvider<List<StudentFeeItem>>((ref) async {
  return ref.read(paymentsRepositoryProvider).fetchFees();
});

final paymentMutationProvider =
    StateNotifierProvider<PaymentMutationController, AsyncValue<void>>((ref) {
      return PaymentMutationController(ref);
    });

class PaymentMutationController extends StateNotifier<AsyncValue<void>> {
  PaymentMutationController(this.ref) : super(const AsyncValue.data(null));

  final Ref ref;

  Future<void> createPayment({
    required int feeId,
    required double amount,
    required String method,
    required String reference,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref
          .read(paymentsRepositoryProvider)
          .createPayment(
            feeId: feeId,
            amount: amount,
            method: method,
            reference: reference,
          );
    });

    if (!state.hasError) {
      ref.invalidate(paymentsProvider);
      ref.invalidate(feesProvider);
    }
  }
}
