import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paginated_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/provider_cache.dart';
import '../data/payments_repository.dart';
import '../domain/finance_totals.dart';
import '../domain/payment.dart';
import '../domain/student_fee.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return PaymentsRepository(ref.read(dioProvider));
});

final paymentsProvider = FutureProvider.autoDispose<List<PaymentItem>>((
  ref,
) async {
  ref.cacheFor(const Duration(minutes: 3));
  return ref.read(paymentsRepositoryProvider).fetchPayments();
});

class PaymentsPageQuery {
  final int page;
  final int pageSize;
  final String search;
  final String? method;

  const PaymentsPageQuery({
    required this.page,
    required this.pageSize,
    this.search = '',
    this.method,
  });

  @override
  bool operator ==(Object other) {
    return other is PaymentsPageQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.method == method;
  }

  @override
  int get hashCode => Object.hash(page, pageSize, search, method);
}

final paymentsPaginatedProvider = FutureProvider.autoDispose
    .family<PaginatedResult<PaymentItem>, PaymentsPageQuery>((
      ref,
      query,
    ) async {
      ref.cacheFor(const Duration(minutes: 3));
      return ref
          .read(paymentsRepositoryProvider)
          .fetchPaymentsPage(
            page: query.page,
            pageSize: query.pageSize,
            search: query.search,
            method: query.method,
          );
    });

/// Les totaux de la période, comptés par la base.
///
/// Séparé du journal: le journal se pagine et se filtre, les totaux non. Les
/// mélanger avait donné un « montant encaissé » qui ne décrivait que la page
/// affichée.
final financeTotalsProvider = FutureProvider.autoDispose
    .family<TotauxFinance, String>((ref, periode) async {
      ref.cacheFor(const Duration(minutes: 3));
      return ref.read(paymentsRepositoryProvider).totauxDeLaPeriode(periode);
    });

final feesProvider = FutureProvider.autoDispose<List<StudentFeeItem>>((
  ref,
) async {
  ref.cacheFor(const Duration(minutes: 3));
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
      ref.invalidate(paymentsPaginatedProvider);
      ref.invalidate(financeTotalsProvider);
      ref.invalidate(feesProvider);
    }
  }

  Future<void> updatePayment({
    required int paymentId,
    required int feeId,
    required double amount,
    required String method,
    required String reference,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref
          .read(paymentsRepositoryProvider)
          .updatePayment(
            paymentId: paymentId,
            feeId: feeId,
            amount: amount,
            method: method,
            reference: reference,
          );
    });

    if (!state.hasError) {
      ref.invalidate(paymentsProvider);
      ref.invalidate(paymentsPaginatedProvider);
      ref.invalidate(financeTotalsProvider);
      ref.invalidate(feesProvider);
    }
  }

  Future<void> deletePayment({required int paymentId}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref.read(paymentsRepositoryProvider).deletePayment(paymentId);
    });

    if (!state.hasError) {
      ref.invalidate(paymentsProvider);
      ref.invalidate(paymentsPaginatedProvider);
      ref.invalidate(financeTotalsProvider);
      ref.invalidate(feesProvider);
    }
  }
}
