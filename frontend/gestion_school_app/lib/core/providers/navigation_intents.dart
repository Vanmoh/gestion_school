import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminShellNavigationKeyProvider = StateProvider<String?>((ref) => null);

final financeOpenGuidedPaymentIntentProvider = StateProvider<bool>(
	(ref) => false,
);
